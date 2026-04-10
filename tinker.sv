`timescale 1ns/1ps

`define MEM_SIZE  524288
`define PC_START  64'h2000

`define OP_AND    5'h00
`define OP_OR     5'h01
`define OP_XOR    5'h02
`define OP_NOT    5'h03
`define OP_SHFTR  5'h04
`define OP_SHFTRI 5'h05
`define OP_SHFTL  5'h06
`define OP_SHFTLI 5'h07
`define OP_BR     5'h08
`define OP_BRR    5'h09
`define OP_BRR2   5'h0A
`define OP_BRNZ   5'h0B
`define OP_CALL   5'h0C
`define OP_RETURN 5'h0D
`define OP_BRGT   5'h0E
`define OP_PRIV   5'h0F
`define OP_MOV    5'h10
`define OP_MOV1   5'h11
`define OP_MOV2   5'h12
`define OP_MOV3   5'h13
`define OP_ADDF   5'h14
`define OP_SUBF   5'h15
`define OP_MULF   5'h16
`define OP_DIVF   5'h17
`define OP_ADD    5'h18
`define OP_ADDI   5'h19
`define OP_SUB    5'h1A
`define OP_SUBI   5'h1B
`define OP_MUL    5'h1C
`define OP_DIV    5'h1D

module reg_file_module (
    input  wire        clk,
    input  wire        reset,
    input  wire        we,
    input  wire [4:0]  wr_addr,
    input  wire [63:0] wr_data,
    input  wire [4:0]  ra_addr,
    input  wire [4:0]  rb_addr,
    input  wire [4:0]  rc_addr,
    output wire [63:0] ra_data,
    output wire [63:0] rb_data,
    output wire [63:0] rc_data
);
    reg [63:0] registers [0:31];

    assign ra_data = registers[ra_addr];
    assign rb_data = registers[rb_addr];
    assign rc_data = registers[rc_addr];

    integer idx;
    always @(posedge clk) begin
        if (reset) begin
            for (idx = 0; idx < 31; idx = idx + 1)
                registers[idx] <= 64'd0;
            registers[31] <= `MEM_SIZE;
        end else if (we) begin
            registers[wr_addr] <= wr_data;
        end
    end
endmodule

module memory_module (
    input  wire        clk,
    input  wire [63:0] fetch_addr,
    output wire [31:0] fetch_data,
    input  wire [63:0] rd_addr,
    output wire [63:0] rd_data,
    input  wire        wr_en,
    input  wire [63:0] wr_addr,
    input  wire [63:0] wr_data
);
    reg [7:0] bytes [0:`MEM_SIZE-1];

    assign fetch_data = {bytes[fetch_addr+3], bytes[fetch_addr+2],
                         bytes[fetch_addr+1], bytes[fetch_addr]};

    assign rd_data = {bytes[rd_addr+7], bytes[rd_addr+6],
                      bytes[rd_addr+5], bytes[rd_addr+4],
                      bytes[rd_addr+3], bytes[rd_addr+2],
                      bytes[rd_addr+1], bytes[rd_addr]};

    always @(posedge clk) begin
        if (wr_en) begin
            bytes[wr_addr]   <= wr_data[7:0];
            bytes[wr_addr+1] <= wr_data[15:8];
            bytes[wr_addr+2] <= wr_data[23:16];
            bytes[wr_addr+3] <= wr_data[31:24];
            bytes[wr_addr+4] <= wr_data[39:32];
            bytes[wr_addr+5] <= wr_data[47:40];
            bytes[wr_addr+6] <= wr_data[55:48];
            bytes[wr_addr+7] <= wr_data[63:56];
        end
    end
endmodule

module fp_add (
    input  wire [63:0] a,
    input  wire [63:0] b,
    output reg  [63:0] result
);
    wire        sa = a[63],    sb = b[63];
    wire [10:0] ea = a[62:52], eb = b[62:52];
    wire [51:0] ma = a[51:0],  mb = b[51:0];

    wire a_nan = (ea == 11'h7FF) && (ma != 52'b0);
    wire b_nan = (eb == 11'h7FF) && (mb != 52'b0);
    wire a_inf = (ea == 11'h7FF) && (ma == 52'b0);
    wire b_inf = (eb == 11'h7FF) && (mb == 52'b0);

    wire [53:0] siga = {1'b0, 1'b1, ma};
    wire [53:0] sigb = {1'b0, 1'b1, mb};
    wire [10:0] dab = ea - eb;
    wire [10:0] dba = eb - ea;

    reg [53:0] sa_al, sb_al;
    reg [10:0] er;
    reg        sr;
    reg [53:0] sum;
    integer    sh;

    always @(*) begin
        if (a_nan)
            result = a;
        else if (b_nan)
            result = b;
        else if (a_inf && b_inf) begin
            if (sa == sb) result = a;
            else          result = 64'h7FF8000000000000;
        end
        else if (a_inf) result = a;
        else if (b_inf) result = b;
        else if (a[62:0] == 0 && b[62:0] == 0) result = 64'b0;
        else if (a[62:0] == 0) result = b;
        else if (b[62:0] == 0) result = a;
        else begin
            if (ea >= eb) begin
                er    = ea;
                sa_al = siga;
                sb_al = (dab >= 54) ? 54'd0 : (sigb >> dab);
            end else begin
                er    = eb;
                sa_al = (dba >= 54) ? 54'd0 : (siga >> dba);
                sb_al = sigb;
            end

            if (sa == sb) begin
                sum = sa_al + sb_al;
                sr  = sa;
            end else if (sa_al >= sb_al) begin
                sum = sa_al - sb_al;
                sr  = sa;
            end else begin
                sum = sb_al - sa_al;
                sr  = sb;
            end

            if (sum == 0) begin
                result = 64'b0;
            end else begin
                if (sum[53]) begin
                    sum = sum >> 1;
                    er  = er + 11'd1;
                end else begin
                    sh = 0;
                    while (sum[52] == 0 && sh < 52) begin
                        sum = sum << 1;
                        sh  = sh + 1;
                    end
                    er = (er > sh[10:0]) ? (er - sh[10:0]) : 11'd0;
                end
                if (er >= 11'h7FF)
                    result = {sr, 11'h7FF, 52'b0};
                else
                    result = {sr, er, sum[51:0]};
            end
        end
    end
endmodule

module fp_sub (
    input  wire [63:0] a,
    input  wire [63:0] b,
    output wire [63:0] result
);
    fp_add u (.a(a), .b({~b[63], b[62:0]}), .result(result));
endmodule

module fp_mul (
    input  wire [63:0] a,
    input  wire [63:0] b,
    output reg  [63:0] result
);
    wire        sr   = a[63] ^ b[63];
    wire [10:0] ea   = a[62:52];
    wire [10:0] eb   = b[62:52];
    wire [51:0] ma   = a[51:0];
    wire [51:0] mb   = b[51:0];
    wire a_nan  = (ea == 11'h7FF) && (ma != 52'b0);
    wire b_nan  = (eb == 11'h7FF) && (mb != 52'b0);
    wire a_inf  = (ea == 11'h7FF) && (ma == 52'b0);
    wire b_inf  = (eb == 11'h7FF) && (mb == 52'b0);
    wire a_zero = (a[62:0] == 63'b0);
    wire b_zero = (b[62:0] == 63'b0);

    wire [52:0] siga = (ea == 0) ? {1'b0, ma} : {1'b1, ma};
    wire [52:0] sigb = (eb == 0) ? {1'b0, mb} : {1'b1, mb};

    reg [6:0] a_lz, b_lz;
    integer   k;
    always @(*) begin
        a_lz = 7'd52;
        for (k = 0; k <= 52; k = k + 1)
            if (siga[k]) a_lz = 7'd52 - k[6:0];
        b_lz = 7'd52;
        for (k = 0; k <= 52; k = k + 1)
            if (sigb[k]) b_lz = 7'd52 - k[6:0];
    end

    wire [52:0] siga_n = siga << a_lz;
    wire [52:0] sigb_n = sigb << b_lz;
    wire [105:0] prod = siga_n * sigb_n;

    wire signed [12:0] ea_eff = (ea == 0) ? (13'sd1 - {6'b0, a_lz}) : {2'b0, ea};
    wire signed [12:0] eb_eff = (eb == 0) ? (13'sd1 - {6'b0, b_lz}) : {2'b0, eb};
    wire signed [12:0] er = ea_eff + eb_eff - 13'sd1023;

    reg [7:0] p_lead;
    integer   j;
    always @(*) begin
        p_lead = 8'd0;
        for (j = 0; j <= 105; j = j + 1)
            if (prod[j]) p_lead = j[7:0];
    end

    wire signed [12:0] er_final = er + {5'b0, p_lead} - 13'sd104;
    wire [7:0]   rshift_p     = (p_lead >= 52) ? (p_lead - 8'd52) : 8'd0;
    wire [7:0]   lshift_p     = (p_lead <  52) ? (8'd52 - p_lead) : 8'd0;
    wire [105:0] prod_aligned = (p_lead >= 52) ? (prod >> rshift_p) : (prod << lshift_p);
    wire [51:0]  mant_norm    = prod_aligned[51:0];

    wire signed [12:0] sub_shift_s = 13'sd1 - er_final;
    wire [6:0]         sub_shift7  = sub_shift_s[6:0];
    wire [51:0]        mant_sub    = (sub_shift_s <= 0) ? mant_norm :
                                     (sub_shift_s > 52) ? 52'b0    :
                                     (prod_aligned >> sub_shift7) & 52'hFFFFFFFFFFFFF;

    always @(*) begin
        if (a_nan)        result = a;
        else if (b_nan)   result = b;
        else if (a_inf || b_inf) result = {sr, 11'h7FF, 52'b0};
        else if (a_zero || b_zero) result = {sr, 63'b0};
        else if (prod == 0) result = {sr, 63'b0};
        else if (er_final >= 13'sd2047) result = {sr, 11'h7FF, 52'b0};
        else if (er_final <= 13'sd0)    result = {sr, 11'b0, mant_sub};
        else result = {sr, er_final[10:0], mant_norm};
    end
endmodule

module fp_div (
    input  wire [63:0] a,
    input  wire [63:0] b,
    output reg  [63:0] result
);
    wire        sr   = a[63] ^ b[63];
    wire [10:0] ea   = a[62:52];
    wire [10:0] eb   = b[62:52];
    wire [51:0] ma   = a[51:0];
    wire [51:0] mb   = b[51:0];
    wire a_nan  = (ea == 11'h7FF) && (ma != 52'b0);
    wire b_nan  = (eb == 11'h7FF) && (mb != 52'b0);
    wire a_inf  = (ea == 11'h7FF) && (ma == 52'b0);
    wire b_inf  = (eb == 11'h7FF) && (mb == 52'b0);
    wire a_zero = (a[62:0] == 63'b0);
    wire b_zero = (b[62:0] == 63'b0);

    wire [52:0] siga_raw = (ea == 0) ? {1'b0, ma} : {1'b1, ma};
    wire [52:0] sigb_raw = (eb == 0) ? {1'b0, mb} : {1'b1, mb};

    reg [6:0] a_lz, b_lz;
    integer   k;
    always @(*) begin
        a_lz = 7'd52;
        for (k = 0; k <= 52; k = k + 1)
            if (siga_raw[k]) a_lz = 7'd52 - k[6:0];
        b_lz = 7'd52;
        for (k = 0; k <= 52; k = k + 1)
            if (sigb_raw[k]) b_lz = 7'd52 - k[6:0];
    end

    wire [52:0] siga_n = siga_raw << a_lz;
    wire [52:0] sigb_n = sigb_raw << b_lz;

    wire signed [12:0] ea_eff = (ea == 0) ? (13'sd1 - {6'b0, a_lz}) : {2'b0, ea};
    wire signed [12:0] eb_eff = (eb == 0) ? (13'sd1 - {6'b0, b_lz}) : {2'b0, eb};
    wire signed [12:0] er = ea_eff - eb_eff + 13'sd1023;

    wire [156:0] num  = {siga_n, 104'b0};
    wire [104:0] quot = num / {52'b0, sigb_n};

    reg [7:0] q_lead;
    integer   j;
    always @(*) begin
        q_lead = 8'd0;
        for (j = 0; j <= 104; j = j + 1)
            if (quot[j]) q_lead = j[7:0];
    end

    wire signed [12:0] er_final  = er + {5'b0, q_lead} - 13'sd104;
    wire [7:0]   rshift          = (q_lead >= 52) ? (q_lead - 8'd52) : 8'd0;
    wire [7:0]   lshift          = (q_lead < 52)  ? (8'd52 - q_lead) : 8'd0;
    wire [104:0] quot_aligned    = (q_lead >= 52) ? (quot >> rshift) : (quot << lshift);
    wire [51:0]  mant_norm       = quot_aligned[51:0];

    wire signed [12:0] sub_shift  = 13'sd1 - er_final;
    wire [6:0]         sub_shift7 = sub_shift[6:0];
    wire [51:0]        mant_sub   = (sub_shift <= 0) ? mant_norm :
                                    (sub_shift > 52)  ? 52'b0    :
                                    (quot_aligned >> sub_shift7) & 52'hFFFFFFFFFFFFF;

    always @(*) begin
        if (a_nan)               result = a;
        else if (b_nan)          result = b;
        else if (a_zero && !b_zero) result = {sr, 63'b0};
        else if (b_zero)         result = {sr, 11'h7FF, 52'b0};
        else if (a_inf && !b_inf) result = {sr, 11'h7FF, 52'b0};
        else if (b_inf && !a_inf) result = {sr, 63'b0};
        else if (a_inf && b_inf) result = 64'h7FF8000000000000;
        else if (er_final >= 13'sd2047) result = {sr, 11'h7FF, 52'b0};
        else if (er_final <= 13'sd0)    result = {sr, 11'b0, mant_sub};
        else result = {sr, er_final[10:0], mant_norm};
    end
endmodule

module alu_fpu (
    input  wire [4:0]  opcode,
    input  wire [63:0] rs_val,
    input  wire [63:0] rt_val,
    input  wire [63:0] rd_val,
    input  wire [11:0] imm12,
    output reg  [63:0] result
);
    wire [63:0] fadd_o, fsub_o, fmul_o, fdiv_o;
    fp_add fadd (.a(rs_val), .b(rt_val), .result(fadd_o));
    fp_sub fsub (.a(rs_val), .b(rt_val), .result(fsub_o));
    fp_mul fmul (.a(rs_val), .b(rt_val), .result(fmul_o));
    fp_div fdiv (.a(rs_val), .b(rt_val), .result(fdiv_o));

    always @(*) begin
        case (opcode)
            `OP_AND   : result = rs_val & rt_val;
            `OP_OR    : result = rs_val | rt_val;
            `OP_XOR   : result = rs_val ^ rt_val;
            `OP_NOT   : result = ~rs_val;
            `OP_SHFTR : result = rs_val >> rt_val;
            `OP_SHFTRI: result = rd_val >> imm12;
            `OP_SHFTL : result = rs_val << rt_val;
            `OP_SHFTLI: result = rd_val << imm12;
            `OP_ADD   : result = rs_val + rt_val;
            `OP_ADDI  : result = rd_val + {52'b0, imm12};
            `OP_SUB   : result = rs_val - rt_val;
            `OP_SUBI  : result = rd_val - {52'b0, imm12};
            `OP_MUL   : result = rs_val * rt_val;
            `OP_DIV   : result = (rt_val != 0) ? rs_val / rt_val : 64'b0;
            `OP_ADDF  : result = fadd_o;
            `OP_SUBF  : result = fsub_o;
            `OP_MULF  : result = fmul_o;
            `OP_DIVF  : result = fdiv_o;
            `OP_MOV1  : result = rs_val;
            `OP_MOV2  : result = (rd_val & 64'hFFFFFFFFFFFFF000) | {52'b0, imm12};
            default   : result = 64'b0;
        endcase
    end
endmodule

module tinker_core (
    input  clk,
    input  reset,
    output logic hlt
);
    localparam S_IF  = 3'd0;
    localparam S_ID  = 3'd1;
    localparam S_EX  = 3'd2;
    localparam S_MEM = 3'd3;
    localparam S_WB  = 3'd4;

    reg [2:0]  state;
    reg [63:0] pc;
    reg [63:0] pc_if;
    reg [31:0] instr_reg;

    wire [4:0]  opcode_w = instr_reg[31:27];
    wire [4:0]  rd_w     = instr_reg[26:22];
    wire [4:0]  rs_w     = instr_reg[21:17];
    wire [4:0]  rt_w     = instr_reg[16:12];
    wire [11:0] imm12_w  = instr_reg[11:0];

    reg [4:0]  opcode_r, rd_r, rs_r, rt_r;
    reg [11:0] imm12_r;
    reg [63:0] rs_val_r, rt_val_r, rd_val_r;
    reg [63:0] r31_r;
    reg [63:0] alu_result_r;
    reg [63:0] mem_addr_r;
    reg [63:0] store_data_r;
    reg [63:0] next_pc_r;
    reg [63:0] mem_data_r;

    wire [31:0] fetch_data;
    reg  [63:0] mem_rd_addr;
    wire [63:0] mem_rd_data;
    reg         mem_wr_en;
    reg  [63:0] mem_wr_addr;
    reg  [63:0] mem_wr_data;

    memory_module memory (
        .clk(clk), .fetch_addr(pc), .fetch_data(fetch_data),
        .rd_addr(mem_rd_addr), .rd_data(mem_rd_data),
        .wr_en(mem_wr_en), .wr_addr(mem_wr_addr), .wr_data(mem_wr_data)
    );

    reg         reg_we;
    reg  [4:0]  reg_wr_addr;
    reg  [63:0] reg_wr_data;
    wire [63:0] rs_val, rt_val, rd_val;

    reg_file_module reg_file (
        .clk(clk), .reset(reset),
        .we(reg_we), .wr_addr(reg_wr_addr), .wr_data(reg_wr_data),
        .ra_addr(rs_w), .rb_addr(rt_w), .rc_addr(rd_w),
        .ra_data(rs_val), .rb_data(rt_val), .rc_data(rd_val)
    );

    wire [63:0] alu_result;
    alu_fpu alu (
        .opcode(opcode_r), .rs_val(rs_val_r), .rt_val(rt_val_r),
        .rd_val(rd_val_r), .imm12(imm12_r), .result(alu_result)
    );

    wire [63:0] simm_r = {{52{imm12_r[11]}}, imm12_r};

    // combinational control: memory and reg write enables
    always @(*) begin
        mem_wr_en   = 1'b0;
        mem_wr_addr = 64'b0;
        mem_wr_data = 64'b0;
        mem_rd_addr = 64'b0;
        reg_we      = 1'b0;
        reg_wr_addr = rd_r;
        reg_wr_data = 64'b0;

        if (state == S_MEM) begin
            case (opcode_r)
                `OP_MOV:    mem_rd_addr = mem_addr_r;
                `OP_RETURN: mem_rd_addr = mem_addr_r;
                `OP_MOV3: begin
                    mem_wr_en   = 1'b1;
                    mem_wr_addr = mem_addr_r;
                    mem_wr_data = store_data_r;
                end
                `OP_CALL: begin
                    mem_wr_en   = 1'b1;
                    mem_wr_addr = mem_addr_r;
                    mem_wr_data = store_data_r;
                end
                default: ;
            endcase
        end else if (state == S_WB) begin
            reg_we      = 1'b1;
            reg_wr_addr = rd_r;
            reg_wr_data = (opcode_r == `OP_MOV) ? mem_data_r : alu_result_r;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IF;
            pc    <= `PC_START;
            pc_if <= `PC_START;
            hlt   <= 1'b0;
            instr_reg    <= 32'b0;
            opcode_r     <= 5'b0;
            rd_r <= 5'b0; rs_r <= 5'b0; rt_r <= 5'b0;
            imm12_r      <= 12'b0;
            rs_val_r     <= 64'b0;
            rt_val_r     <= 64'b0;
            rd_val_r     <= 64'b0;
            r31_r        <= 64'b0;
            alu_result_r <= 64'b0;
            mem_addr_r   <= 64'b0;
            store_data_r <= 64'b0;
            next_pc_r    <= 64'b0;
            mem_data_r   <= 64'b0;
        end else if (!hlt) begin
            case (state)
                S_IF: begin
                    instr_reg <= fetch_data;
                    pc_if     <= pc;
                    state     <= S_ID;
                end

                S_ID: begin
                    opcode_r <= opcode_w;
                    rd_r     <= rd_w;
                    rs_r     <= rs_w;
                    rt_r     <= rt_w;
                    imm12_r  <= imm12_w;
                    rs_val_r <= rs_val;
                    rt_val_r <= rt_val;
                    rd_val_r <= rd_val;
                    r31_r    <= reg_file.registers[31];
                    state    <= S_EX;
                end

                S_EX: begin
                    alu_result_r <= alu_result;
                    case (opcode_r)
                        `OP_MOV: begin
                            mem_addr_r <= rs_val_r + simm_r;
                            state <= S_MEM;
                        end
                        `OP_MOV3: begin
                            mem_addr_r   <= rd_val_r + simm_r;
                            store_data_r <= rs_val_r;
                            state <= S_MEM;
                        end
                        `OP_CALL: begin
                            mem_addr_r   <= r31_r - 64'd8;
                            store_data_r <= pc_if + 64'd4;
                            next_pc_r    <= rd_val_r;
                            state <= S_MEM;
                        end
                        `OP_RETURN: begin
                            mem_addr_r <= r31_r - 64'd8;
                            state <= S_MEM;
                        end
                        `OP_BR: begin
                            pc    <= rd_val_r;
                            state <= S_IF;
                        end
                        `OP_BRR: begin
                            pc    <= pc_if + rd_val_r;
                            state <= S_IF;
                        end
                        `OP_BRR2: begin
                            pc    <= pc_if + simm_r;
                            state <= S_IF;
                        end
                        `OP_BRNZ: begin
                            pc    <= (rs_val_r != 64'd0) ? rd_val_r : (pc_if + 64'd4);
                            state <= S_IF;
                        end
                        `OP_BRGT: begin
                            pc    <= (rs_val_r > rt_val_r) ? rd_val_r : (pc_if + 64'd4);
                            state <= S_IF;
                        end
                        `OP_PRIV: begin
                            if (imm12_r == 12'h000)
                                hlt <= 1'b1;
                            pc    <= pc_if + 64'd4;
                            state <= S_IF;
                        end
                        default: state <= S_WB;
                    endcase
                end

                S_MEM: begin
                    case (opcode_r)
                        `OP_MOV: begin
                            mem_data_r <= mem_rd_data;
                            state <= S_WB;
                        end
                        `OP_MOV3: begin
                            pc    <= pc_if + 64'd4;
                            state <= S_IF;
                        end
                        `OP_CALL: begin
                            pc    <= next_pc_r;
                            state <= S_IF;
                        end
                        `OP_RETURN: begin
                            pc    <= mem_rd_data;
                            state <= S_IF;
                        end
                        default: begin
                            pc    <= pc_if + 64'd4;
                            state <= S_IF;
                        end
                    endcase
                end

                S_WB: begin
                    pc    <= pc_if + 64'd4;
                    state <= S_IF;
                end

                default: state <= S_IF;
            endcase
        end
    end

endmodule
