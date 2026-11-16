// Auto-generated 0-BSRAM dynamic UI text ROM (80x45 char grid, 16x16 per cell)
module ui_text_rom (
    input             I_clk       ,
    input      [6:0]  I_col       , // 0..79
    input      [5:0]  I_row       , // 0..44
    input      [3:0]  I_span      ,
    input      [1:0]  I_win       ,
    input      [1:0]  I_det       ,
    input      [1:0]  I_trc       ,
    input             I_trc_sub   ,
    input      [1:0]  I_ref_mode  ,
    input      [2:0]  I_avg       ,
    input      [1:0]  I_view      ,
    input             I_mkr_en    ,
    input             I_mkr_fine  ,
    input             I_mkr_delta ,
    input             I_mkr_track ,
    input      [2:0]  I_harm_mode ,
    input      [1:0]  I_yscale    ,
    input      [2:0]  I_yref      ,
    input             I_yscale_ref,
    input      [3:0]  I_lim_lvl   ,
    input             I_lim_sub   ,
    input             I_lim_fail  ,
    input      [2:0]  I_trig_mode ,
    input      [3:0]  I_trig_lvl  ,
    input             I_trig_sub  ,
    input      [3:0]  I_vscale    ,
    input      [3:0]  I_tscale    ,
    input             I_vt_sel    ,
    input      [47:0] I_pk_f_str  , // 6 ASCII chars (8b each)
    input      [23:0] I_pk_f_unit , // 3 ASCII chars (8b each)
    input      [47:0] I_pk_db_str , // 6 ASCII chars (8b each)
    input      [31:0] I_vpp_str   , // 4 ASCII chars (8b each)
    input      [47:0] I_wf_str    , // 6 ASCII chars
    input      [23:0] I_wf_unit   , // 3 ASCII chars
    input      [23:0] I_duty_str  , // 3 ASCII chars
    input      [39:0] I_h2_str    , // 5 ASCII chars (8b each)
    input      [39:0] I_h3_str    , // 5 ASCII chars (8b each)
    input      [39:0] I_h4_str    , // 5 ASCII chars (8b each)
    input      [39:0] I_h5_str    , // 5 ASCII chars (8b each)
    input      [31:0] I_thd_str   , // 4 ASCII chars (8b each)
    input      [31:0] I_sfdr_str  , // 4 ASCII chars (8b each)
    input      [47:0] I_mkr_f_str , // 6 ASCII chars (8b each)
    input      [47:0] I_mkr_db_str, // 6 ASCII chars (8b each)
    input      [47:0] I_dmkr_f_str, // 6 ASCII chars (8b each)
    input      [47:0] I_dmkr_db_str,// 6 ASCII chars (8b each)
    input      [47:0] I_h1_f_str  , // 6 ASCII chars (8b each)
    input      [47:0] I_h2_f_str  , // 6 ASCII chars (8b each)
    input      [47:0] I_h3_f_str  , // 6 ASCII chars (8b each)
    input      [47:0] I_h4_f_str  , // 6 ASCII chars (8b each)
    input      [47:0] I_h5_f_str  , // 6 ASCII chars (8b each)
    input      [47:0] I_t1_str    , // 6 ASCII chars
    input      [47:0] I_dt_str    , // 6 ASCII chars
    input      [47:0] I_idt_str   , // 6 ASCII chars
    input      [23:0] I_t_unit    , // 3 ASCII chars
    input      [31:0] I_tx1_str   , // 4 ASCII chars
    input      [31:0] I_tx2_str   , // 4 ASCII chars
    input      [31:0] I_tx3_str   , // 4 ASCII chars
    input      [31:0] I_tx4_str   , // 4 ASCII chars
    output reg [6:0]  O_char
);

    reg [6:0] ch_next;

    function [6:0] y_axis_char;
        input [6:0] att_db;
        input [1:0] col;
        reg [6:0] rem;
        reg [3:0] d1, d0;
        begin
            if (att_db == 7'd0) begin
                y_axis_char = (col == 2'd3) ? 7'h30 : 7'h20;
            end else if (att_db < 7'd10) begin
                case (col)
                    2'd2: y_axis_char = 7'h2D;
                    2'd3: y_axis_char = 7'h30 + {3'd0, att_db[3:0]};
                    default: y_axis_char = 7'h20;
                endcase
            end else if (att_db < 7'd100) begin
                d1 = (att_db >= 7'd90) ? 4'd9 : (att_db >= 7'd80) ? 4'd8 :
                     (att_db >= 7'd70) ? 4'd7 : (att_db >= 7'd60) ? 4'd6 :
                     (att_db >= 7'd50) ? 4'd5 : (att_db >= 7'd40) ? 4'd4 :
                     (att_db >= 7'd30) ? 4'd3 : (att_db >= 7'd20) ? 4'd2 : 4'd1;
                d0 = att_db - (({3'd0, d1} << 3) + ({3'd0, d1} << 1));
                case (col)
                    2'd1: y_axis_char = 7'h2D;
                    2'd2: y_axis_char = 7'h30 + {3'd0, d1};
                    2'd3: y_axis_char = 7'h30 + {3'd0, d0};
                    default: y_axis_char = 7'h20;
                endcase
            end else begin
                rem = att_db - 7'd100;
                d1  = (rem >= 7'd20) ? 4'd2 : (rem >= 7'd10) ? 4'd1 : 4'd0;
                d0  = rem - (({3'd0, d1} << 3) + ({3'd0, d1} << 1));
                case (col)
                    2'd0: y_axis_char = 7'h2D;
                    2'd1: y_axis_char = 7'h31;
                    2'd2: y_axis_char = 7'h30 + {3'd0, d1};
                    2'd3: y_axis_char = 7'h30 + {3'd0, d0};
                endcase
            end
        end
    endfunction

    reg [1:0] yscale_r, trc_r, ref_mode_r, view_r;
    reg [2:0] yref_r, trig_r;
    reg [3:0] vscale_r, tscale_r, trig_lvl_r, lim_lvl_r, span_r;
    reg       yscale_ref_r, vt_sel_r, trig_sub_r, trc_sub_r, lim_sub_r, lim_fail_r;
    reg [23:0] t_unit_r;
    reg [27:0] y0_str, y1_str, y2_str, y3_str, y4_str;
    reg [39:0] x1_lbl, x2_lbl, x3_lbl;
    reg [55:0] x4_lbl;
    reg [48:0] vscl_str, tscl_str, trig_str, tlvl_str, trc2_str, ref2_str;

    wire [6:0] yref_db = (yref_r == 3'd1) ? 7'd10 :
                         (yref_r == 3'd2) ? 7'd20 :
                         (yref_r == 3'd3) ? 7'd30 :
                         (yref_r == 3'd4) ? 7'd40 : 7'd0;
    wire [6:0] ystep_db = (yscale_r == 2'd1) ? 7'd8 :
                          (yscale_r == 2'd2) ? 7'd4 : 7'd20; // 4 divs per tick

    reg [41:0] tv_lbl;
    always @(*) begin
        case (vscale_r)
            4'd1:    tv_lbl = {7'h32,7'h2E,7'h30, 7'h31,7'h2E,7'h30}; // 2.0 / 1.0
            4'd2:    tv_lbl = {7'h31,7'h2E,7'h30, 7'h30,7'h2E,7'h35}; // 1.0 / 0.5
            4'd3:    tv_lbl = {7'h2E,7'h35,7'h56, 7'h2E,7'h32,7'h35}; // .5V / .25
            4'd4:    tv_lbl = {7'h33,7'h33,7'h33, 7'h31,7'h36,7'h37}; // 333 / 167
            4'd5:    tv_lbl = {7'h32,7'h35,7'h30, 7'h31,7'h32,7'h35}; // 250 / 125
            4'd6:    tv_lbl = {7'h31,7'h36,7'h37, 7'h38,7'h33,7'h6D}; // 167 / 83m
            4'd7:    tv_lbl = {7'h31,7'h32,7'h35, 7'h36,7'h32,7'h6D}; // 125 / 62m
            4'd8:    tv_lbl = {7'h38,7'h33,7'h6D, 7'h34,7'h32,7'h6D}; // 83m / 42m
            4'd9:    tv_lbl = {7'h36,7'h32,7'h6D, 7'h33,7'h31,7'h6D}; // 62m / 31m
            4'd10:   tv_lbl = {7'h34,7'h32,7'h6D, 7'h32,7'h31,7'h6D}; // 42m / 21m
            4'd11:   tv_lbl = {7'h33,7'h31,7'h6D, 7'h31,7'h36,7'h6D}; // 31m / 16m
            4'd12:   tv_lbl = {7'h31,7'h36,7'h6D, 7'h38,7'h6D,7'h56}; // 16m / 8mV
            4'd13:   tv_lbl = {7'h38,7'h6D,7'h56, 7'h34,7'h6D,7'h56}; // 8mV / 4mV
            default: tv_lbl = {7'h46,7'h53,7'h20, 7'h35,7'h30,7'h25}; // FS  / 50%
        endcase
    end

    always @(posedge I_clk) begin
        yscale_r     <= I_yscale;
        yref_r       <= I_yref;
        yscale_ref_r <= I_yscale_ref;
        view_r       <= I_view;
        span_r       <= I_span;
        lim_lvl_r    <= I_lim_lvl;
        lim_sub_r    <= I_lim_sub;
        lim_fail_r   <= I_lim_fail;
        trig_r       <= I_trig_mode;
        trig_lvl_r   <= I_trig_lvl;
        trig_sub_r   <= I_trig_sub;
        trc_r        <= I_trc;
        trc_sub_r    <= I_trc_sub;
        ref_mode_r   <= I_ref_mode;
        vscale_r     <= I_vscale;
        tscale_r     <= I_tscale;
        vt_sel_r     <= I_vt_sel;
        t_unit_r     <= I_t_unit;
        if (view_r == 2'd2) begin
            x1_lbl <= {I_tx1_str, 8'h20};
            x2_lbl <= {I_tx2_str, 8'h20};
            x3_lbl <= {I_tx3_str, 8'h20};
            x4_lbl <= {I_tx4_str, t_unit_r[23:8], 8'h20};
        end else begin
            case (span_r)
                4'd0:  begin x1_lbl <= "250k "; x2_lbl <= "500k "; x3_lbl <= "750k "; x4_lbl <= "1MHz   "; end
                4'd1:  begin x1_lbl <= "50k  "; x2_lbl <= "100k "; x3_lbl <= "150k "; x4_lbl <= "200kHz "; end
                4'd2:  begin x1_lbl <= "12.5k"; x2_lbl <= "25k  "; x3_lbl <= "37.5k"; x4_lbl <= "50kHz  "; end
                4'd3:  begin x1_lbl <= "2.5k "; x2_lbl <= "5.0k "; x3_lbl <= "7.5k "; x4_lbl <= "10kHz  "; end
                4'd4:  begin x1_lbl <= "250  "; x2_lbl <= "500  "; x3_lbl <= "750  "; x4_lbl <= "1kHz   "; end
                4'd5:  begin x1_lbl <= "50   "; x2_lbl <= "100  "; x3_lbl <= "150  "; x4_lbl <= "200Hz  "; end
                4'd6:  begin x1_lbl <= "6.75M"; x2_lbl <= "13.5M"; x3_lbl <= "20.2M"; x4_lbl <= "27MHz  "; end
                4'd7:  begin x1_lbl <= "125k "; x2_lbl <= "250k "; x3_lbl <= "375k "; x4_lbl <= "500kHz "; end
                4'd8:  begin x1_lbl <= "25k  "; x2_lbl <= "50k  "; x3_lbl <= "75k  "; x4_lbl <= "100kHz "; end
                4'd9:  begin x1_lbl <= "675k "; x2_lbl <= "1.35M"; x3_lbl <= "2.02M"; x4_lbl <= "2.7MHz "; end
                4'd10: begin x1_lbl <= "1.35M"; x2_lbl <= "2.70M"; x3_lbl <= "4.05M"; x4_lbl <= "5.4MHz "; end
                4'd11: begin x1_lbl <= "3.38M"; x2_lbl <= "6.75M"; x3_lbl <= "10.1M"; x4_lbl <= "13.5MHz"; end
                4'd12: begin x1_lbl <= "5.0k "; x2_lbl <= "10k  "; x3_lbl <= "15k  "; x4_lbl <= "20kHz  "; end
                4'd13: begin x1_lbl <= "1.25k"; x2_lbl <= "2.5k "; x3_lbl <= "3.75k"; x4_lbl <= "5.0kHz "; end
                4'd14: begin x1_lbl <= "500  "; x2_lbl <= "1.0k "; x3_lbl <= "1.5k "; x4_lbl <= "2.0kHz "; end
                4'd15: begin x1_lbl <= "125  "; x2_lbl <= "250  "; x3_lbl <= "375  "; x4_lbl <= "500Hz  "; end
            endcase
        end

        if (view_r == 2'd2) begin
            y0_str <= {7'h2B, tv_lbl[41:21]};
            y1_str <= {7'h2B, tv_lbl[20:0]};
            y2_str <= (vscale_r >= 4'd4) ? {7'h20, 7'h30, 7'h6D, 7'h56} : {7'h20, 7'h30, 7'h56, 7'h20};
            y3_str <= {7'h2D, tv_lbl[20:0]};
            y4_str <= {7'h2D, tv_lbl[41:21]};
        end else begin
            y0_str <= {y_axis_char(yref_db, 2'd0), y_axis_char(yref_db, 2'd1), y_axis_char(yref_db, 2'd2), y_axis_char(yref_db, 2'd3)};
            y1_str <= {y_axis_char(yref_db + ystep_db, 2'd0), y_axis_char(yref_db + ystep_db, 2'd1), y_axis_char(yref_db + ystep_db, 2'd2), y_axis_char(yref_db + ystep_db, 2'd3)};
            y2_str <= {y_axis_char(yref_db + {ystep_db[5:0], 1'b0}, 2'd0), y_axis_char(yref_db + {ystep_db[5:0], 1'b0}, 2'd1), y_axis_char(yref_db + {ystep_db[5:0], 1'b0}, 2'd2), y_axis_char(yref_db + {ystep_db[5:0], 1'b0}, 2'd3)};
            y3_str <= {y_axis_char(yref_db + {ystep_db[5:0], 1'b0} + ystep_db, 2'd0), y_axis_char(yref_db + {ystep_db[5:0], 1'b0} + ystep_db, 2'd1), y_axis_char(yref_db + {ystep_db[5:0], 1'b0} + ystep_db, 2'd2), y_axis_char(yref_db + {ystep_db[5:0], 1'b0} + ystep_db, 2'd3)};
            y4_str <= {y_axis_char(yref_db + {ystep_db[4:0], 2'b00}, 2'd0), y_axis_char(yref_db + {ystep_db[4:0], 2'b00}, 2'd1), y_axis_char(yref_db + {ystep_db[4:0], 2'b00}, 2'd2), y_axis_char(yref_db + {ystep_db[4:0], 2'b00}, 2'd3)};
        end

        case (vscale_r)
            4'd1:    vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h2E, 7'h32, 7'h35}; // *V:x.25
            4'd2:    vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h30, 7'h2E, 7'h35}; // *V:x0.5
            4'd3:    vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h31, 7'h2E, 7'h30}; // *V:x1.0
            4'd4:    vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h31, 7'h2E, 7'h35}; // *V:x1.5
            4'd5:    vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h32, 7'h2E, 7'h30}; // *V:x2.0
            4'd6:    vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h33, 7'h2E, 7'h30}; // *V:x3.0
            4'd7:    vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h34, 7'h2E, 7'h30}; // *V:x4.0
            4'd8:    vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h36, 7'h2E, 7'h30}; // *V:x6.0
            4'd9:    vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h38, 7'h2E, 7'h30}; // *V:x8.0
            4'd10:   vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h31, 7'h32, 7'h20}; // *V:x12
            4'd11:   vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h31, 7'h36, 7'h20}; // *V:x16
            4'd12:   vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h33, 7'h32, 7'h20}; // *V:x32
            4'd13:   vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h78, 7'h36, 7'h34, 7'h20}; // *V:x64
            default: vscl_str <= {!vt_sel_r ? 7'h2A : 7'h20, 7'h56, 7'h3A, 7'h41, 7'h55, 7'h54, 7'h4F}; // *V:AUTO
        endcase

        case (tscale_r)
            4'd0:    tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h2E, 7'h32, 7'h35}; // *T:x.25
            4'd1:    tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h30, 7'h2E, 7'h35}; // *T:x0.5
            4'd3:    tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h31, 7'h2E, 7'h33}; // *T:x1.3
            4'd4:    tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h32, 7'h2E, 7'h30}; // *T:x2.0
            4'd5:    tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h32, 7'h2E, 7'h37}; // *T:x2.7
            4'd6:    tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h34, 7'h2E, 7'h30}; // *T:x4.0
            4'd7:    tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h35, 7'h2E, 7'h33}; // *T:x5.3
            4'd8:    tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h38, 7'h2E, 7'h30}; // *T:x8.0
            4'd9:    tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h31, 7'h36, 7'h20}; // *T:x16
            4'd10:   tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h33, 7'h32, 7'h20}; // *T:x32
            4'd11:   tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h36, 7'h34, 7'h20}; // *T:x64
            default: tscl_str <= {vt_sel_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h78, 7'h31, 7'h2E, 7'h30}; // *T:x1.0
        endcase

        case (trig_r)
            3'd1:    trig_str <= {!trig_sub_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h52, 7'h49, 7'h53, 7'h45}; // *T:RISE
            3'd2:    trig_str <= {!trig_sub_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h46, 7'h41, 7'h4C, 7'h4C}; // *T:FALL
            3'd3:    trig_str <= {!trig_sub_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h53, 7'h4E, 7'h47, 7'h4C}; // *T:SNGL
            3'd4:    trig_str <= {!trig_sub_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h48, 7'h4F, 7'h4C, 7'h44}; // *T:HOLD
            default: trig_str <= {!trig_sub_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h41, 7'h55, 7'h54, 7'h4F}; // *T:AUTO
        endcase

        case (trig_lvl_r)
            4'd0:    tlvl_str <= {trig_sub_r ? 7'h2A : 7'h20, 7'h4C, 7'h3A, 7'h2D, 7'h35, 7'h30, 7'h25}; // *L:-50%
            4'd1:    tlvl_str <= {trig_sub_r ? 7'h2A : 7'h20, 7'h4C, 7'h3A, 7'h2D, 7'h33, 7'h37, 7'h25}; // *L:-37%
            4'd2:    tlvl_str <= {trig_sub_r ? 7'h2A : 7'h20, 7'h4C, 7'h3A, 7'h2D, 7'h32, 7'h35, 7'h25}; // *L:-25%
            4'd3:    tlvl_str <= {trig_sub_r ? 7'h2A : 7'h20, 7'h4C, 7'h3A, 7'h2D, 7'h31, 7'h32, 7'h25}; // *L:-12%
            4'd5:    tlvl_str <= {trig_sub_r ? 7'h2A : 7'h20, 7'h4C, 7'h3A, 7'h2B, 7'h31, 7'h32, 7'h25}; // *L:+12%
            4'd6:    tlvl_str <= {trig_sub_r ? 7'h2A : 7'h20, 7'h4C, 7'h3A, 7'h2B, 7'h32, 7'h35, 7'h25}; // *L:+25%
            4'd7:    tlvl_str <= {trig_sub_r ? 7'h2A : 7'h20, 7'h4C, 7'h3A, 7'h2B, 7'h33, 7'h37, 7'h25}; // *L:+37%
            4'd8:    tlvl_str <= {trig_sub_r ? 7'h2A : 7'h20, 7'h4C, 7'h3A, 7'h2B, 7'h35, 7'h30, 7'h25}; // *L:+50%
            default: tlvl_str <= {trig_sub_r ? 7'h2A : 7'h20, 7'h4C, 7'h3A, 7'h4D, 7'h49, 7'h44, 7'h20}; // *L:MID
        endcase

        case (trc_r)
            2'd1:    trc2_str <= {!trc_sub_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h4D, 7'h41, 7'h58, 7'h48}; // *T:MAXH
            2'd2:    trc2_str <= {!trc_sub_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h4D, 7'h49, 7'h4E, 7'h48}; // *T:MINH
            2'd3:    trc2_str <= {!trc_sub_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h56, 7'h49, 7'h45, 7'h57}; // *T:VIEW
            default: trc2_str <= {!trc_sub_r ? 7'h2A : 7'h20, 7'h54, 7'h3A, 7'h43, 7'h4C, 7'h52, 7'h20}; // *T:CLR
        endcase

        case (ref_mode_r)
            2'd1:    ref2_str <= {trc_sub_r ? 7'h2A : 7'h20, 7'h52, 7'h3A, 7'h4F, 7'h4E, 7'h20, 7'h20}; // *R:ON
            2'd2:    ref2_str <= {trc_sub_r ? 7'h2A : 7'h20, 7'h52, 7'h3A, 7'h43, 7'h41, 7'h50, 7'h20}; // *R:CAP
            default: ref2_str <= {trc_sub_r ? 7'h2A : 7'h20, 7'h52, 7'h3A, 7'h4F, 7'h46, 7'h46, 7'h20}; // *R:OFF
        endcase
    end

    function [6:0] pick4;
        input [27:0] str;
        input [1:0]  idx;
        begin
            case (idx)
                2'd0: pick4 = str[27:21];
                2'd1: pick4 = str[20:14];
                2'd2: pick4 = str[13:7];
                2'd3: pick4 = str[6:0];
            endcase
        end
    endfunction

    function [6:0] pick7;
        input [48:0] str;
        input [2:0]  idx;
        begin
            case (idx)
                3'd0: pick7 = str[48:42];
                3'd1: pick7 = str[41:35];
                3'd2: pick7 = str[34:28];
                3'd3: pick7 = str[27:21];
                3'd4: pick7 = str[20:14];
                3'd5: pick7 = str[13:7];
                3'd6: pick7 = str[6:0];
                default: pick7 = 7'h20;
            endcase
        end
    endfunction

    reg [48:0] span_str, rbw_str, swt_str, win_str, det_str, trc_str, avg_str;
    always @(*) begin
        case (span_r)
            4'd0:  begin span_str = {7'h31, 7'h2E, 7'h30, 7'h30, 7'h4D, 7'h48, 7'h7A}; rbw_str = {7'h31, 7'h2E, 7'h34, 7'h36, 7'h6B, 7'h48, 7'h7A}; swt_str = {7'h32, 7'h2E, 7'h30, 7'h35, 7'h6D, 7'h73}; end
            4'd1:  begin span_str = {7'h32, 7'h30, 7'h30, 7'h6B, 7'h48, 7'h7A, 7'h20}; rbw_str = {7'h32, 7'h39, 7'h33, 7'h48, 7'h7A, 7'h20, 7'h20}; swt_str = {7'h31, 7'h30, 7'h2E, 7'h32, 7'h6D, 7'h73}; end
            4'd2:  begin span_str = {7'h35, 7'h30, 7'h2E, 7'h30, 7'h6B, 7'h48, 7'h7A}; rbw_str = {7'h37, 7'h33, 7'h2E, 7'h32, 7'h48, 7'h7A, 7'h20}; swt_str = {7'h34, 7'h31, 7'h2E, 7'h30, 7'h6D, 7'h73}; end
            4'd3:  begin span_str = {7'h31, 7'h30, 7'h2E, 7'h30, 7'h6B, 7'h48, 7'h7A}; rbw_str = {7'h31, 7'h34, 7'h2E, 7'h36, 7'h48, 7'h7A, 7'h20}; swt_str = {7'h32, 7'h30, 7'h35, 7'h6D, 7'h73, 7'h20}; end
            4'd4:  begin span_str = {7'h31, 7'h2E, 7'h30, 7'h30, 7'h6B, 7'h48, 7'h7A}; rbw_str = {7'h31, 7'h2E, 7'h34, 7'h36, 7'h48, 7'h7A, 7'h20}; swt_str = {7'h30, 7'h2E, 7'h35, 7'h31, 7'h73, 7'h20}; end
            4'd5:  begin span_str = {7'h32, 7'h30, 7'h30, 7'h48, 7'h7A, 7'h20, 7'h20}; rbw_str = {7'h30, 7'h2E, 7'h32, 7'h39, 7'h48, 7'h7A, 7'h20}; swt_str = {7'h30, 7'h2E, 7'h36, 7'h34, 7'h73, 7'h20}; end
            4'd6:  begin span_str = {7'h32, 7'h37, 7'h2E, 7'h30, 7'h4D, 7'h48, 7'h7A}; rbw_str = {7'h33, 7'h39, 7'h2E, 7'h36, 7'h6B, 7'h48, 7'h7A}; swt_str = {7'h37, 7'h35, 7'h2E, 7'h39, 7'h75, 7'h73}; end
            4'd7:  begin span_str = {7'h35, 7'h30, 7'h30, 7'h6B, 7'h48, 7'h7A, 7'h20}; rbw_str = {7'h37, 7'h33, 7'h32, 7'h48, 7'h7A, 7'h20, 7'h20}; swt_str = {7'h34, 7'h2E, 7'h31, 7'h30, 7'h6D, 7'h73}; end
            4'd8:  begin span_str = {7'h31, 7'h30, 7'h30, 7'h6B, 7'h48, 7'h7A, 7'h20}; rbw_str = {7'h31, 7'h34, 7'h36, 7'h48, 7'h7A, 7'h20, 7'h20}; swt_str = {7'h32, 7'h30, 7'h2E, 7'h35, 7'h6D, 7'h73}; end
            4'd9:  begin span_str = {7'h32, 7'h2E, 7'h37, 7'h30, 7'h4D, 7'h48, 7'h7A}; rbw_str = {7'h33, 7'h2E, 7'h39, 7'h36, 7'h6B, 7'h48, 7'h7A}; swt_str = {7'h37, 7'h35, 7'h39, 7'h75, 7'h73, 7'h20}; end
            4'd10: begin span_str = {7'h35, 7'h2E, 7'h34, 7'h30, 7'h4D, 7'h48, 7'h7A}; rbw_str = {7'h37, 7'h2E, 7'h39, 7'h31, 7'h6B, 7'h48, 7'h7A}; swt_str = {7'h33, 7'h37, 7'h39, 7'h75, 7'h73, 7'h20}; end
            4'd11: begin span_str = {7'h31, 7'h33, 7'h2E, 7'h35, 7'h4D, 7'h48, 7'h7A}; rbw_str = {7'h31, 7'h39, 7'h2E, 7'h38, 7'h6B, 7'h48, 7'h7A}; swt_str = {7'h31, 7'h35, 7'h32, 7'h75, 7'h73, 7'h20}; end
            4'd12: begin span_str = {7'h32, 7'h30, 7'h2E, 7'h30, 7'h6B, 7'h48, 7'h7A}; rbw_str = {7'h32, 7'h39, 7'h2E, 7'h33, 7'h48, 7'h7A, 7'h20}; swt_str = {7'h31, 7'h30, 7'h32, 7'h6D, 7'h73, 7'h20}; end
            4'd13: begin span_str = {7'h35, 7'h2E, 7'h30, 7'h30, 7'h6B, 7'h48, 7'h7A}; rbw_str = {7'h37, 7'h2E, 7'h33, 7'h32, 7'h48, 7'h7A, 7'h20}; swt_str = {7'h34, 7'h31, 7'h30, 7'h6D, 7'h73, 7'h20}; end
            4'd14: begin span_str = {7'h32, 7'h2E, 7'h30, 7'h30, 7'h6B, 7'h48, 7'h7A}; rbw_str = {7'h32, 7'h2E, 7'h39, 7'h33, 7'h48, 7'h7A, 7'h20}; swt_str = {7'h30, 7'h2E, 7'h35, 7'h31, 7'h73, 7'h20}; end
            4'd15: begin span_str = {7'h35, 7'h30, 7'h30, 7'h48, 7'h7A, 7'h20, 7'h20}; rbw_str = {7'h30, 7'h2E, 7'h37, 7'h33, 7'h48, 7'h7A, 7'h20}; swt_str = {7'h30, 7'h2E, 7'h35, 7'h31, 7'h73, 7'h20}; end
            default: begin span_str = 49'd0; rbw_str = 49'd0; swt_str = 49'd0; end
        endcase
        case (I_win)
            2'd0: win_str = {7'h48, 7'h41, 7'h4E, 7'h4E, 7'h20, 7'h20, 7'h20};
            2'd1: win_str = {7'h52, 7'h45, 7'h43, 7'h54, 7'h20, 7'h20, 7'h20};
            2'd2: win_str = {7'h42, 7'h4C, 7'h41, 7'h43, 7'h4B, 7'h4D, 7'h4E};
            2'd3: win_str = {7'h46, 7'h4C, 7'h41, 7'h54, 7'h54, 7'h4F, 7'h50};
        endcase
        case (I_det)
            2'd0: det_str = {7'h50, 7'h4F, 7'h53, 7'h2D, 7'h50, 7'h4B, 7'h20};
            2'd1: det_str = {7'h41, 7'h56, 7'h45, 7'h52, 7'h41, 7'h47, 7'h45};
            2'd2: det_str = {7'h4E, 7'h45, 7'h47, 7'h2D, 7'h50, 7'h4B, 7'h20};
            2'd3: det_str = {7'h53, 7'h41, 7'h4D, 7'h50, 7'h4C, 7'h45, 7'h20};
        endcase
        case (I_trc)
            2'd0: trc_str = {7'h43, 7'h4C, 7'h52, 7'h2D, 7'h57, 7'h52, 7'h54};
            2'd1: trc_str = {7'h4D, 7'h41, 7'h58, 7'h48, 7'h4F, 7'h4C, 7'h44};
            2'd2: trc_str = {7'h4D, 7'h49, 7'h4E, 7'h48, 7'h4F, 7'h4C, 7'h44};
            2'd3: trc_str = {7'h56, 7'h49, 7'h45, 7'h57, 7'h20, 7'h20, 7'h20};
        endcase
        case (I_avg)
            3'd0: avg_str = {7'h41, 7'h55, 7'h54, 7'h4F, 7'h20, 7'h20, 7'h20};
            3'd1: avg_str = {7'h78, 7'h31, 7'h20, 7'h20, 7'h20, 7'h20, 7'h20};
            3'd2: avg_str = {7'h78, 7'h34, 7'h20, 7'h20, 7'h20, 7'h20, 7'h20};
            3'd3: avg_str = {7'h78, 7'h31, 7'h36, 7'h20, 7'h20, 7'h20, 7'h20};
            3'd4: avg_str = {7'h78, 7'h36, 7'h34, 7'h20, 7'h20, 7'h20, 7'h20};
            default: avg_str = {7'h41, 7'h55, 7'h54, 7'h4F, 7'h20, 7'h20, 7'h20};
        endcase
    end

    wire [4:0] row39_sel = (view_r == 2'd2) ? 5'd16 : {1'b0, span_r};

    always @(*) begin
        ch_next = 7'h20;
        case (I_row)
            6'd1: begin
                case (I_col)
                    7'd2: ch_next = 7'h41; // A
                    7'd3: ch_next = 7'h44; // D
                    7'd4: ch_next = 7'h39; // 9
                    7'd5: ch_next = 7'h32; // 2
                    7'd6: ch_next = 7'h32; // 2
                    7'd7: ch_next = 7'h36; // 6
                    7'd9: ch_next = 7'h53; // S
                    7'd10: ch_next = 7'h50; // P
                    7'd11: ch_next = 7'h45; // E
                    7'd12: ch_next = 7'h43; // C
                    7'd13: ch_next = 7'h54; // T
                    7'd14: ch_next = 7'h52; // R
                    7'd15: ch_next = 7'h55; // U
                    7'd16: ch_next = 7'h4D; // M
                    7'd18: ch_next = 7'h41; // A
                    7'd19: ch_next = 7'h4E; // N
                    7'd20: ch_next = 7'h41; // A
                    7'd21: ch_next = 7'h4C; // L
                    7'd22: ch_next = 7'h59; // Y
                    7'd23: ch_next = 7'h5A; // Z
                    7'd24: ch_next = 7'h45; // E
                    7'd25: ch_next = 7'h52; // R
                    7'd30: ch_next = 7'h53; // S
                    7'd31: ch_next = 7'h50; // P
                    7'd32: ch_next = 7'h41; // A
                    7'd33: ch_next = 7'h4E; // N
                    7'd34: ch_next = 7'h3A; // :
                    7'd35, 7'd36, 7'd37, 7'd38, 7'd39, 7'd40, 7'd41: ch_next = pick7(span_str, I_col - 7'd35);
                    7'd44: ch_next = 7'h52; // R
                    7'd45: ch_next = 7'h42; // B
                    7'd46: ch_next = 7'h57; // W
                    7'd47: ch_next = 7'h3A; // :
                    7'd48, 7'd49, 7'd50, 7'd51, 7'd52, 7'd53, 7'd54: ch_next = pick7(rbw_str, I_col - 7'd48);
                    7'd57: ch_next = 7'h53; // S
                    7'd58: ch_next = 7'h57; // W
                    7'd59: ch_next = 7'h54; // T
                    7'd60: ch_next = 7'h3A; // :
                    7'd61, 7'd62, 7'd63, 7'd64, 7'd65, 7'd66, 7'd67: ch_next = pick7(swt_str, I_col - 7'd61);
                    default: ch_next = 7'h20;
                endcase
            end
            6'd3: begin
                case (I_col)
                    7'd2: ch_next = 7'h50; // P
                    7'd3: ch_next = 7'h45; // E
                    7'd4: ch_next = 7'h41; // A
                    7'd5: ch_next = 7'h4B; // K
                    7'd6: ch_next = 7'h3A; // :
                    7'd8:  ch_next = I_pk_f_str[46:40];
                    7'd9:  ch_next = I_pk_f_str[38:32];
                    7'd10: ch_next = I_pk_f_str[30:24];
                    7'd11: ch_next = I_pk_f_str[22:16];
                    7'd12: ch_next = I_pk_f_str[14:8];
                    7'd13: ch_next = I_pk_f_str[6:0];
                    7'd15: ch_next = I_pk_f_unit[22:16];
                    7'd16: ch_next = I_pk_f_unit[14:8];
                    7'd17: ch_next = I_pk_f_unit[6:0];
                    7'd20: ch_next = I_pk_db_str[46:40];
                    7'd21: ch_next = I_pk_db_str[38:32];
                    7'd22: ch_next = I_pk_db_str[30:24];
                    7'd23: ch_next = I_pk_db_str[22:16];
                    7'd24: ch_next = I_pk_db_str[14:8];
                    7'd25: ch_next = I_pk_db_str[6:0];
                    7'd27: ch_next = 7'h64; // d
                    7'd28: ch_next = 7'h42; // B
                    7'd29: ch_next = 7'h46; // F
                    7'd30: ch_next = 7'h53; // S
                    7'd34: ch_next = 7'h56; // V
                    7'd35: ch_next = 7'h50; // P
                    7'd36: ch_next = 7'h50; // P
                    7'd37: ch_next = 7'h3A; // :
                    7'd38: ch_next = I_vpp_str[30:24];
                    7'd39: ch_next = I_vpp_str[22:16];
                    7'd40: ch_next = I_vpp_str[14:8];
                    7'd41: ch_next = I_vpp_str[6:0];
                    7'd42: ch_next = 7'h6D; // m
                    7'd43: ch_next = 7'h56; // V
                    7'd48: ch_next = 7'h56; // V
                    7'd49: ch_next = 7'h49; // I
                    7'd50: ch_next = 7'h45; // E
                    7'd51: ch_next = 7'h57; // W
                    7'd52: ch_next = 7'h3A; // :
                    7'd53: ch_next = (I_view == 2'd0) ? 7'h53 : (I_view == 2'd1) ? 7'h53 : 7'h54;
                    7'd54: ch_next = (I_view == 2'd0) ? 7'h50 : (I_view == 2'd1) ? 7'h50 : 7'h49;
                    7'd55: ch_next = (I_view == 2'd0) ? 7'h45 : (I_view == 2'd1) ? 7'h4C : 7'h4D;
                    7'd56: ch_next = (I_view == 2'd0) ? 7'h43 : (I_view == 2'd1) ? 7'h54 : 7'h45;
                    7'd59: ch_next = 7'h44; // D
                    7'd60: ch_next = 7'h54; // T
                    7'd61: ch_next = 7'h3A; // :
                    7'd62: ch_next = I_duty_str[22:16];
                    7'd63: ch_next = I_duty_str[14:8];
                    7'd64: ch_next = I_duty_str[6:0];
                    7'd65: ch_next = 7'h25; // %
                    default: ch_next = 7'h20;
                endcase
            end
            6'd5: begin
                case (I_col)
                    7'd2: ch_next = 7'h48; // H
                    7'd3: ch_next = 7'h32; // 2
                    7'd4: ch_next = 7'h3A; // :
                    7'd5:  ch_next = I_h2_str[38:32];
                    7'd6:  ch_next = I_h2_str[30:24];
                    7'd7:  ch_next = I_h2_str[22:16];
                    7'd8:  ch_next = I_h2_str[14:8];
                    7'd9:  ch_next = I_h2_str[6:0];
                    7'd12: ch_next = 7'h48; // H
                    7'd13: ch_next = 7'h33; // 3
                    7'd14: ch_next = 7'h3A; // :
                    7'd15: ch_next = I_h3_str[38:32];
                    7'd16: ch_next = I_h3_str[30:24];
                    7'd17: ch_next = I_h3_str[22:16];
                    7'd18: ch_next = I_h3_str[14:8];
                    7'd19: ch_next = I_h3_str[6:0];
                    7'd22: ch_next = 7'h48; // H
                    7'd23: ch_next = 7'h34; // 4
                    7'd24: ch_next = 7'h3A; // :
                    7'd25: ch_next = I_h4_str[38:32];
                    7'd26: ch_next = I_h4_str[30:24];
                    7'd27: ch_next = I_h4_str[22:16];
                    7'd28: ch_next = I_h4_str[14:8];
                    7'd29: ch_next = I_h4_str[6:0];
                    7'd32: ch_next = 7'h48; // H
                    7'd33: ch_next = 7'h35; // 5
                    7'd34: ch_next = 7'h3A; // :
                    7'd35: ch_next = I_h5_str[38:32];
                    7'd36: ch_next = I_h5_str[30:24];
                    7'd37: ch_next = I_h5_str[22:16];
                    7'd38: ch_next = I_h5_str[14:8];
                    7'd39: ch_next = I_h5_str[6:0];
                    7'd42: ch_next = 7'h54; // T
                    7'd43: ch_next = 7'h48; // H
                    7'd44: ch_next = 7'h44; // D
                    7'd45: ch_next = 7'h3A; // :
                    7'd46: ch_next = I_thd_str[30:24];
                    7'd47: ch_next = I_thd_str[22:16];
                    7'd48: ch_next = I_thd_str[14:8];
                    7'd49: ch_next = I_thd_str[6:0];
                    7'd50: ch_next = 7'h25; // %
                    7'd53: ch_next = 7'h57; // W
                    7'd54: ch_next = 7'h46; // F
                    7'd55: ch_next = 7'h3A; // :
                    7'd56: ch_next = I_wf_str[46:40];
                    7'd57: ch_next = I_wf_str[38:32];
                    7'd58: ch_next = I_wf_str[30:24];
                    7'd59: ch_next = I_wf_str[22:16];
                    7'd60: ch_next = I_wf_str[14:8];
                    7'd61: ch_next = I_wf_str[6:0];
                    7'd63: ch_next = I_wf_unit[22:16];
                    7'd64: ch_next = I_wf_unit[14:8];
                    7'd65: ch_next = I_wf_unit[6:0];
                    default: ch_next = 7'h20;
                endcase
            end
            6'd6: begin
                if (I_col <= 7'd3)
                    ch_next = pick4(y0_str, I_col[1:0]);
                else begin
                    if (lim_sub_r) begin
                        case (I_col)
                            7'd71: ch_next = 7'h2A; // *
                            7'd72: ch_next = 7'h4C; // L
                            7'd73: ch_next = 7'h49; // I
                            7'd74: ch_next = 7'h4D; // M
                            7'd75: ch_next = 7'h49; // I
                            7'd76: ch_next = 7'h54; // T
                            default: ch_next = 7'h20;
                        endcase
                    end else begin
                        case (I_col)
                            7'd71: ch_next = yscale_ref_r ? 7'h2A : 7'h20;
                            7'd72: ch_next = 7'h52; // R
                            7'd73: ch_next = 7'h45; // E
                            7'd74: ch_next = 7'h46; // F
                            7'd75: ch_next = (yref_r == 3'd0) ? 7'h20 : 7'h2D;
                            7'd76: ch_next = (yref_r == 3'd0) ? 7'h20 : (7'h30 + {4'd0, yref_r});
                            7'd77: ch_next = 7'h30;
                            default: ch_next = 7'h20;
                        endcase
                    end
                end
            end
            6'd7: begin
                if (lim_sub_r) begin
                    if (lim_lvl_r == 4'd0) begin
                        case (I_col)
                            7'd72: ch_next = 7'h4F; // O
                            7'd73: ch_next = 7'h46; // F
                            7'd74: ch_next = 7'h46; // F
                            default: ch_next = 7'h20;
                        endcase
                    end else begin
                        case (I_col)
                            7'd72: ch_next = 7'h2D; // -
                            7'd73: ch_next = 7'h30 + {3'd0, lim_lvl_r};
                            7'd74: ch_next = 7'h30; // 0
                            7'd75: ch_next = 7'h64; // d
                            7'd76: ch_next = 7'h42; // B
                            default: ch_next = 7'h20;
                        endcase
                    end
                end else begin
                    case (I_col)
                        7'd71: ch_next = !yscale_ref_r ? 7'h2A : 7'h20;
                        7'd72: ch_next = 7'h53; // S
                        7'd73: ch_next = 7'h43; // C
                        7'd74: ch_next = 7'h4C; // L
                        7'd75: ch_next = (yscale_r == 2'd1) ? 7'h32 : (yscale_r == 2'd2) ? 7'h31 : 7'h35;
                        7'd76: ch_next = 7'h64;
                        7'd77: ch_next = 7'h42;
                        default: ch_next = 7'h20;
                    endcase
                end
            end
            6'd10: begin
                case (I_col)
                    7'd71: ch_next = 7'h57; // W
                    7'd72: ch_next = 7'h49; // I
                    7'd73: ch_next = 7'h4E; // N
                    7'd74: ch_next = 7'h44; // D
                    7'd75: ch_next = 7'h4F; // O
                    7'd76: ch_next = 7'h57; // W
                    default: ch_next = 7'h20;
                endcase
            end
            6'd11: begin
                if (I_col >= 7'd71 && I_col <= 7'd77)
                    ch_next = pick7(win_str, I_col - 7'd71);
            end
            6'd14: begin
                if (I_col <= 7'd3)
                    ch_next = pick4(y1_str, I_col[1:0]);
                else begin
                    case (I_col)
                        7'd71: ch_next = 7'h44; // D
                        7'd72: ch_next = 7'h45; // E
                        7'd73: ch_next = 7'h54; // T
                        7'd74: ch_next = 7'h45; // E
                        7'd75: ch_next = 7'h43; // C
                        7'd76: ch_next = 7'h54; // T
                        default: ch_next = 7'h20;
                    endcase
                end
            end
            6'd15: begin
                if (I_col >= 7'd71 && I_col <= 7'd77)
                    ch_next = pick7(det_str, I_col - 7'd71);
            end
            6'd18: begin
                if (I_col >= 7'd71 && I_col <= 7'd77)
                    ch_next = pick7(trc2_str, I_col - 7'd71);
            end
            6'd19: begin
                if (I_col >= 7'd71 && I_col <= 7'd77)
                    ch_next = pick7(ref2_str, I_col - 7'd71);
            end
            6'd22: begin
                if (I_col <= 7'd3)
                    ch_next = pick4(y2_str, I_col[1:0]);
                else begin
                    case (I_col)
                        7'd71: ch_next = 7'h41; // A
                        7'd72: ch_next = 7'h56; // V
                        7'd73: ch_next = 7'h47; // G
                        default: ch_next = 7'h20;
                    endcase
                end
            end
            6'd23: begin
                if (I_col >= 7'd71 && I_col <= 7'd77)
                    ch_next = pick7(avg_str, I_col - 7'd71);
            end
            6'd26: begin
                case (I_col)
                    7'd71: ch_next = 7'h53; // S
                    7'd72: ch_next = 7'h50; // P
                    7'd73: ch_next = 7'h41; // A
                    7'd74: ch_next = 7'h4E; // N
                    default: ch_next = 7'h20;
                endcase
            end
            6'd27: begin
                if (I_col >= 7'd71 && I_col <= 7'd77)
                    ch_next = pick7(span_str, I_col - 7'd71);
            end
            6'd30: begin
                if (I_col <= 7'd3)
                    ch_next = pick4(y3_str, I_col[1:0]);
                else begin
                    case (I_col)
                        7'd71: ch_next = 7'h4D; // M
                        7'd72: ch_next = 7'h41; // A
                        7'd73: ch_next = 7'h52; // R
                        7'd74: ch_next = 7'h4B; // K
                        7'd75: ch_next = 7'h45; // E
                        7'd76: ch_next = 7'h52; // R
                        default: ch_next = 7'h20;
                    endcase
                end
            end
            6'd31: begin
                if (I_col >= 7'd71 && I_col <= 7'd76) begin
                    if (!I_mkr_en) begin
                        case (I_col)
                            7'd71: ch_next = 7'h4F; // O
                            7'd72: ch_next = 7'h46; // F
                            7'd73: ch_next = 7'h46; // F
                            default: ch_next = 7'h20;
                        endcase
                    end else if (I_mkr_track) begin
                        case (I_col)
                            7'd71: ch_next = 7'h54; // T
                            7'd72: ch_next = 7'h52; // R
                            7'd73: ch_next = 7'h41; // A
                            7'd74: ch_next = 7'h43; // C
                            7'd75: ch_next = 7'h4B; // K
                            default: ch_next = 7'h20;
                        endcase
                    end else if (I_mkr_delta) begin
                        case (I_col)
                            7'd71: ch_next = 7'h44; // D
                            7'd72: ch_next = 7'h45; // E
                            7'd73: ch_next = 7'h4C; // L
                            7'd74: ch_next = 7'h54; // T
                            7'd75: ch_next = 7'h41; // A
                            default: ch_next = 7'h20;
                        endcase
                    end else if (I_mkr_fine) begin
                        case (I_col)
                            7'd71: ch_next = 7'h46; // F
                            7'd72: ch_next = 7'h49; // I
                            7'd73: ch_next = 7'h4E; // N
                            7'd74: ch_next = 7'h45; // E
                            default: ch_next = 7'h20;
                        endcase
                    end else begin
                        case (I_col)
                            7'd71: ch_next = 7'h43; // C
                            7'd72: ch_next = 7'h4F; // O
                            7'd73: ch_next = 7'h41; // A
                            7'd74: ch_next = 7'h52; // R
                            7'd75: ch_next = 7'h53; // S
                            7'd76: ch_next = 7'h45; // E
                            default: ch_next = 7'h20;
                        endcase
                    end
                end
            end
            6'd34: begin
                if (I_col >= 7'd71 && I_col <= 7'd77)
                    ch_next = pick7(trig_str, I_col - 7'd71);
            end
            6'd35: begin
                if (I_col >= 7'd71 && I_col <= 7'd77)
                    ch_next = pick7(tlvl_str, I_col - 7'd71);
            end
            6'd38: begin
                if (I_col <= 7'd3)
                    ch_next = pick4(y4_str, I_col[1:0]);
                else if (I_col >= 7'd71 && I_col <= 7'd77)
                    ch_next = pick7(vscl_str, I_col - 7'd71);
            end
            6'd39: begin
                if (I_col >= 7'd71 && I_col <= 7'd77) begin
                    ch_next = pick7(tscl_str, I_col - 7'd71);
                end else begin
                    case (I_col)
                        7'd4:  ch_next = 7'h30;
                        7'd18: ch_next = x1_lbl[38:32];
                        7'd19: ch_next = x1_lbl[30:24];
                        7'd20: ch_next = x1_lbl[22:16];
                        7'd21: ch_next = x1_lbl[14:8];
                        7'd22: ch_next = x1_lbl[6:0];
                        7'd34: ch_next = x2_lbl[38:32];
                        7'd35: ch_next = x2_lbl[30:24];
                        7'd36: ch_next = x2_lbl[22:16];
                        7'd37: ch_next = x2_lbl[14:8];
                        7'd38: ch_next = x2_lbl[6:0];
                        7'd49: ch_next = x3_lbl[38:32];
                        7'd50: ch_next = x3_lbl[30:24];
                        7'd51: ch_next = x3_lbl[22:16];
                        7'd52: ch_next = x3_lbl[14:8];
                        7'd53: ch_next = x3_lbl[6:0];
                        7'd63: ch_next = x4_lbl[54:48];
                        7'd64: ch_next = x4_lbl[46:40];
                        7'd65: ch_next = x4_lbl[38:32];
                        7'd66: ch_next = x4_lbl[30:24];
                        7'd67: ch_next = x4_lbl[22:16];
                        7'd68: ch_next = x4_lbl[14:8];
                        7'd69: ch_next = x4_lbl[6:0];
                        default: ch_next = 7'h20;
                    endcase
                end
            end
            6'd41: begin
                case (I_col)
                    7'd4: ch_next = 7'h4B; // K
                    7'd5: ch_next = 7'h31; // 1
                    7'd6: ch_next = 7'h3A; // :
                    7'd7: ch_next = 7'h53; // S
                    7'd8: ch_next = 7'h50; // P
                    7'd9: ch_next = 7'h41; // A
                    7'd10: ch_next = 7'h4E; // N
                    7'd13: ch_next = 7'h4B; // K
                    7'd14: ch_next = 7'h32; // 2
                    7'd15: ch_next = 7'h3A; // :
                    7'd16: ch_next = 7'h56; // V
                    7'd17: ch_next = 7'h49; // I
                    7'd18: ch_next = 7'h45; // E
                    7'd19: ch_next = 7'h57; // W
                    7'd22: ch_next = 7'h4B; // K
                    7'd23: ch_next = 7'h33; // 3
                    7'd24: ch_next = 7'h3A; // :
                    7'd25: ch_next = 7'h41; // A
                    7'd26: ch_next = 7'h55; // U
                    7'd27: ch_next = 7'h54; // T
                    7'd28: ch_next = 7'h4F; // O
                    7'd31: ch_next = 7'h4B; // K
                    7'd32: ch_next = 7'h34; // 4
                    7'd33: ch_next = 7'h3A; // :
                    7'd34: ch_next = 7'h4D; // M
                    7'd35: ch_next = 7'h45; // E
                    7'd36: ch_next = 7'h4E; // N
                    7'd37: ch_next = 7'h55; // U
                    7'd40: ch_next = 7'h4B; // K
                    7'd41: ch_next = 7'h35; // 5
                    7'd42: ch_next = 7'h3A; // :
                    7'd43: ch_next = 7'h57; // W
                    7'd44: ch_next = 7'h49; // I
                    7'd45: ch_next = 7'h4E; // N
                    7'd48: ch_next = 7'h45; // E
                    7'd49: ch_next = 7'h4E; // N
                    7'd50: ch_next = 7'h43; // C
                    7'd51: ch_next = 7'h3A; // :
                    7'd52: ch_next = 7'h41; // A
                    7'd53: ch_next = 7'h44; // D
                    7'd54: ch_next = 7'h4A; // J
                    7'd57: ch_next = 7'h48; // H
                    7'd58: ch_next = 7'h4F; // O
                    7'd59: ch_next = 7'h4C; // L
                    7'd60: ch_next = 7'h44; // D
                    7'd61: ch_next = 7'h3A; // :
                    7'd62: ch_next = 7'h52; // R
                    7'd63: ch_next = 7'h53; // S
                    7'd64: ch_next = 7'h54; // T
                    default: ch_next = 7'h20;
                endcase
            end
            6'd42: begin
                case (I_col)
                    7'd59: ch_next = (lim_lvl_r != 4'd0) ? 7'h4C : 7'h20; // L
                    7'd60: ch_next = (lim_lvl_r != 4'd0) ? 7'h49 : 7'h20; // I
                    7'd61: ch_next = (lim_lvl_r != 4'd0) ? 7'h4D : 7'h20; // M
                    7'd62: ch_next = (lim_lvl_r != 4'd0) ? 7'h3A : 7'h20; // :
                    7'd63: ch_next = (lim_lvl_r != 4'd0) ? (lim_fail_r ? 7'h46 : 7'h50) : 7'h20; // F/P
                    7'd64: ch_next = (lim_lvl_r != 4'd0) ? (lim_fail_r ? 7'h41 : 7'h41) : 7'h20; // A
                    7'd65: ch_next = (lim_lvl_r != 4'd0) ? (lim_fail_r ? 7'h49 : 7'h53) : 7'h20; // I/S
                    7'd66: ch_next = (lim_lvl_r != 4'd0) ? (lim_fail_r ? 7'h4C : 7'h53) : 7'h20; // L/S
                    7'd71: ch_next = 7'h48; // H
                    7'd72: ch_next = 7'h41; // A
                    7'd73: ch_next = 7'h52; // R
                    7'd74: ch_next = 7'h4D; // M
                    7'd76: ch_next = 7'h57; // W
                    7'd77: ch_next = 7'h56; // V
                    default: ch_next = 7'h20;
                endcase
            end
            6'd43: begin
                if (I_col >= 7'd71 && I_col <= 7'd74) begin
                    case (I_harm_mode)
                        3'd0: case (I_col) 7'd71: ch_next=7'h4F; 7'd72: ch_next=7'h46; 7'd73: ch_next=7'h46; default: ch_next=7'h20; endcase
                        3'd1: case (I_col) 7'd71: ch_next=7'h48; 7'd72: ch_next=7'h31; default: ch_next=7'h20; endcase
                        3'd2: case (I_col) 7'd71: ch_next=7'h48; 7'd72: ch_next=7'h32; default: ch_next=7'h20; endcase
                        3'd3: case (I_col) 7'd71: ch_next=7'h48; 7'd72: ch_next=7'h33; default: ch_next=7'h20; endcase
                        3'd4: case (I_col) 7'd71: ch_next=7'h48; 7'd72: ch_next=7'h34; default: ch_next=7'h20; endcase
                        3'd5: case (I_col) 7'd71: ch_next=7'h48; 7'd72: ch_next=7'h35; default: ch_next=7'h20; endcase
                        3'd6: case (I_col) 7'd71: ch_next=7'h48; 7'd72: ch_next=7'h31; 7'd73: ch_next=7'h2D; 7'd74: ch_next=7'h35; default: ch_next=7'h20; endcase
                        3'd7: case (I_col) 7'd71: ch_next=7'h41; 7'd72: ch_next=7'h4C; 7'd73: ch_next=7'h4C; 7'd74: ch_next=7'h35; default: ch_next=7'h20; endcase
                        default: ch_next = 7'h20;
                    endcase
                end else if (I_mkr_en && (I_view == 2'd2)) begin
                    case (I_col)
                        7'd4:  ch_next = 7'h54; // T
                        7'd5:  ch_next = 7'h31; // 1
                        7'd6:  ch_next = 7'h3A; // :
                        7'd8:  ch_next = I_t1_str[46:40];
                        7'd9:  ch_next = I_t1_str[38:32];
                        7'd10: ch_next = I_t1_str[30:24];
                        7'd11: ch_next = I_t1_str[22:16];
                        7'd12: ch_next = I_t1_str[14:8];
                        7'd13: ch_next = I_t1_str[6:0];
                        7'd15: ch_next = I_t_unit[22:16];
                        7'd16: ch_next = I_t_unit[14:8];
                        7'd17: ch_next = I_t_unit[6:0];
                        7'd20: ch_next = I_mkr_delta ? 7'h64 : 7'h20; // d
                        7'd21: ch_next = I_mkr_delta ? 7'h54 : 7'h20; // T
                        7'd22: ch_next = I_mkr_delta ? 7'h3A : 7'h20; // :
                        7'd23: ch_next = I_mkr_delta ? I_dt_str[46:40] : 7'h20;
                        7'd24: ch_next = I_mkr_delta ? I_dt_str[38:32] : 7'h20;
                        7'd25: ch_next = I_mkr_delta ? I_dt_str[30:24] : 7'h20;
                        7'd26: ch_next = I_mkr_delta ? I_dt_str[22:16] : 7'h20;
                        7'd27: ch_next = I_mkr_delta ? I_dt_str[14:8]  : 7'h20;
                        7'd28: ch_next = I_mkr_delta ? I_dt_str[6:0]   : 7'h20;
                        7'd30: ch_next = I_mkr_delta ? I_t_unit[22:16] : 7'h20;
                        7'd31: ch_next = I_mkr_delta ? I_t_unit[14:8]  : 7'h20;
                        7'd32: ch_next = I_mkr_delta ? I_t_unit[6:0]   : 7'h20;
                        7'd35: ch_next = I_mkr_delta ? 7'h31 : 7'h20; // 1
                        7'd36: ch_next = I_mkr_delta ? 7'h2F : 7'h20; // /
                        7'd37: ch_next = I_mkr_delta ? 7'h64 : 7'h20; // d
                        7'd38: ch_next = I_mkr_delta ? 7'h54 : 7'h20; // T
                        7'd39: ch_next = I_mkr_delta ? 7'h3A : 7'h20; // :
                        7'd40: ch_next = I_mkr_delta ? I_idt_str[46:40] : 7'h20;
                        7'd41: ch_next = I_mkr_delta ? I_idt_str[38:32] : 7'h20;
                        7'd42: ch_next = I_mkr_delta ? I_idt_str[30:24] : 7'h20;
                        7'd43: ch_next = I_mkr_delta ? I_idt_str[22:16] : 7'h20;
                        7'd44: ch_next = I_mkr_delta ? I_idt_str[14:8]  : 7'h20;
                        7'd45: ch_next = I_mkr_delta ? I_idt_str[6:0]   : 7'h20;
                        7'd47: ch_next = I_mkr_delta ? I_pk_f_unit[22:16] : 7'h20;
                        7'd48: ch_next = I_mkr_delta ? I_pk_f_unit[14:8]  : 7'h20;
                        7'd49: ch_next = I_mkr_delta ? I_pk_f_unit[6:0]   : 7'h20;
                        default: ch_next = 7'h20;
                    endcase
                end else if (I_mkr_en) begin
                    case (I_col)
                    7'd4: ch_next = 7'h4D; // M
                    7'd5: ch_next = 7'h41; // A
                    7'd6: ch_next = 7'h52; // R
                    7'd7: ch_next = 7'h4B; // K
                    7'd8: ch_next = 7'h45; // E
                    7'd9: ch_next = 7'h52; // R
                    7'd10: ch_next = 7'h3A; // :
                        7'd12: ch_next = I_mkr_f_str[46:40];
                        7'd13: ch_next = I_mkr_f_str[38:32];
                        7'd14: ch_next = I_mkr_f_str[30:24];
                        7'd15: ch_next = I_mkr_f_str[22:16];
                        7'd16: ch_next = I_mkr_f_str[14:8];
                        7'd17: ch_next = I_mkr_f_str[6:0];
                        7'd19: ch_next = I_pk_f_unit[22:16];
                        7'd20: ch_next = I_pk_f_unit[14:8];
                        7'd21: ch_next = I_pk_f_unit[6:0];
                        7'd24: ch_next = I_mkr_db_str[46:40];
                        7'd25: ch_next = I_mkr_db_str[38:32];
                        7'd26: ch_next = I_mkr_db_str[30:24];
                        7'd27: ch_next = I_mkr_db_str[22:16];
                        7'd28: ch_next = I_mkr_db_str[14:8];
                        7'd29: ch_next = I_mkr_db_str[6:0];
                    7'd31: ch_next = 7'h64; // d
                    7'd32: ch_next = 7'h42; // B
                    7'd33: ch_next = 7'h46; // F
                    7'd34: ch_next = 7'h53; // S
                    7'd37: ch_next = I_mkr_delta ? 7'h44 : 7'h20; // D
                    7'd38: ch_next = I_mkr_delta ? 7'h3A : 7'h20; // :
                    7'd40: ch_next = I_mkr_delta ? I_dmkr_f_str[46:40] : 7'h20;
                    7'd41: ch_next = I_mkr_delta ? I_dmkr_f_str[38:32] : 7'h20;
                    7'd42: ch_next = I_mkr_delta ? I_dmkr_f_str[30:24] : 7'h20;
                    7'd43: ch_next = I_mkr_delta ? I_dmkr_f_str[22:16] : 7'h20;
                    7'd44: ch_next = I_mkr_delta ? I_dmkr_f_str[14:8]  : 7'h20;
                    7'd45: ch_next = I_mkr_delta ? I_dmkr_f_str[6:0]   : 7'h20;
                    7'd47: ch_next = I_mkr_delta ? I_pk_f_unit[22:16]  : 7'h20;
                    7'd48: ch_next = I_mkr_delta ? I_pk_f_unit[14:8]   : 7'h20;
                    7'd49: ch_next = I_mkr_delta ? I_pk_f_unit[6:0]    : 7'h20;
                    7'd52: ch_next = I_mkr_delta ? I_dmkr_db_str[46:40]: 7'h20;
                    7'd53: ch_next = I_mkr_delta ? I_dmkr_db_str[38:32]: 7'h20;
                    7'd54: ch_next = I_mkr_delta ? I_dmkr_db_str[30:24]: 7'h20;
                    7'd55: ch_next = I_mkr_delta ? I_dmkr_db_str[22:16]: 7'h20;
                    7'd56: ch_next = I_mkr_delta ? I_dmkr_db_str[14:8] : 7'h20;
                    7'd57: ch_next = I_mkr_delta ? I_dmkr_db_str[6:0]  : 7'h20;
                    7'd59: ch_next = I_mkr_delta ? 7'h64 : 7'h20; // d
                    7'd60: ch_next = I_mkr_delta ? 7'h42 : 7'h20; // B
                        default: ch_next = 7'h20;
                    endcase
                end
            end
            6'd44: begin
                case (I_col)
                    7'd4:  ch_next = 7'h48; // H
                    7'd5:  ch_next = 7'h31; // 1
                    7'd6:  ch_next = 7'h3A; // :
                    7'd7:  ch_next = I_h1_f_str[46:40];
                    7'd8:  ch_next = I_h1_f_str[38:32];
                    7'd9:  ch_next = I_h1_f_str[30:24];
                    7'd10: ch_next = I_h1_f_str[22:16];
                    7'd11: ch_next = I_h1_f_str[14:8];
                    7'd12: ch_next = I_h1_f_str[6:0];
                    7'd14: ch_next = 7'h48; // H
                    7'd15: ch_next = 7'h32; // 2
                    7'd16: ch_next = 7'h3A; // :
                    7'd17: ch_next = I_h2_f_str[46:40];
                    7'd18: ch_next = I_h2_f_str[38:32];
                    7'd19: ch_next = I_h2_f_str[30:24];
                    7'd20: ch_next = I_h2_f_str[22:16];
                    7'd21: ch_next = I_h2_f_str[14:8];
                    7'd22: ch_next = I_h2_f_str[6:0];
                    7'd24: ch_next = 7'h48; // H
                    7'd25: ch_next = 7'h33; // 3
                    7'd26: ch_next = 7'h3A; // :
                    7'd27: ch_next = I_h3_f_str[46:40];
                    7'd28: ch_next = I_h3_f_str[38:32];
                    7'd29: ch_next = I_h3_f_str[30:24];
                    7'd30: ch_next = I_h3_f_str[22:16];
                    7'd31: ch_next = I_h3_f_str[14:8];
                    7'd32: ch_next = I_h3_f_str[6:0];
                    7'd34: ch_next = 7'h48; // H
                    7'd35: ch_next = 7'h34; // 4
                    7'd36: ch_next = 7'h3A; // :
                    7'd37: ch_next = I_h4_f_str[46:40];
                    7'd38: ch_next = I_h4_f_str[38:32];
                    7'd39: ch_next = I_h4_f_str[30:24];
                    7'd40: ch_next = I_h4_f_str[22:16];
                    7'd41: ch_next = I_h4_f_str[14:8];
                    7'd42: ch_next = I_h4_f_str[6:0];
                    7'd44: ch_next = 7'h48; // H
                    7'd45: ch_next = 7'h35; // 5
                    7'd46: ch_next = 7'h3A; // :
                    7'd47: ch_next = I_h5_f_str[46:40];
                    7'd48: ch_next = I_h5_f_str[38:32];
                    7'd49: ch_next = I_h5_f_str[30:24];
                    7'd50: ch_next = I_h5_f_str[22:16];
                    7'd51: ch_next = I_h5_f_str[14:8];
                    7'd52: ch_next = I_h5_f_str[6:0];
                    7'd54: ch_next = I_pk_f_unit[22:16];
                    7'd55: ch_next = I_pk_f_unit[14:8];
                    7'd56: ch_next = I_pk_f_unit[6:0];
                    7'd59: ch_next = 7'h53; // S
                    7'd60: ch_next = 7'h46; // F
                    7'd61: ch_next = 7'h44; // D
                    7'd62: ch_next = 7'h52; // R
                    7'd63: ch_next = 7'h3A; // :
                    7'd64: ch_next = I_sfdr_str[30:24];
                    7'd65: ch_next = I_sfdr_str[22:16];
                    7'd66: ch_next = I_sfdr_str[14:8];
                    7'd67: ch_next = I_sfdr_str[6:0];
                    7'd68: ch_next = 7'h64; // d
                    7'd69: ch_next = 7'h42; // B
                    default: ch_next = 7'h20;
                endcase
            end
            default: ch_next = 7'h20;
        endcase
    end

    always @(posedge I_clk) begin
        O_char <= ch_next;
    end

endmodule
