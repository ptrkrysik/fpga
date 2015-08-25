//
// Copyright 2015 National Instruments
//

module noc_block_moving_avg #(
  parameter NOC_ID = 64'hAAD2_0000_0000_0000,
  parameter STR_SINK_FIFOSIZE = 11)
(
  input bus_clk,
  input bus_rst,

  input ce_clk,
  input ce_rst,

  input [63:0] i_tdata,
  input i_tlast,
  input i_tvalid,
  output i_tready,

  output [63:0] o_tdata,
  output o_tlast,
  output o_tvalid,
  input  o_tready,

  output [63:0] debug);

  //----------------------------------------------------------------------------
  // Constants
  //----------------------------------------------------------------------------

  // Settings registers addresses
  localparam SR_NEXT_DST   = 128;
  localparam SR_AXI_CONFIG = 129;
  localparam SR_SUM_LEN    = 192;
  localparam SR_DIVISOR    = 193;
  localparam SR_READBACK   = 255;

  //----------------------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------------------

  // Set next destination in chain
 wire [15:0] next_dst;

  // Readback register address
  wire rb_addr;

  // Number of samples to accumulate
  wire [7:0] sum_len;
  wire sum_len_changed;

  // Sum will be divided by this number
  wire [23:0] divisor;

  // RFNoC Shell
  wire [31:0] set_data;
  wire [7:0]  set_addr;
  wire        set_stb;

  wire clear_tx_seqnum;

  wire [63:0] str_sink_tdata, str_src_tdata;
  wire str_sink_tlast, str_sink_tvalid, str_sink_tready;
  wire str_src_tlast, str_src_tvalid, str_src_tready;

  // AXI Wrapper
  wire [31:0]  m_axis_data_tdata, s_axis_data_tdata;
  wire [127:0] m_axis_data_tuser;
  wire m_axis_data_tlast, m_axis_data_tvalid, m_axis_data_tready;
  wire s_axis_data_tlast, s_axis_data_tvalid, s_axis_data_tready;

  // I part
  wire [15:0] ipart_tdata;
  wire ipart_tlast, ipart_tvalid, ipart_tready;

  // Q part
  wire [15:0] qpart_tdata;
  wire qpart_tlast, qpart_tvalid, qpart_tready;

  // I sum
  wire [23:0] isum_tdata;
  wire isum_tlast, isum_tvalid, isum_tready;

  // Q sum
  wire [23:0] qsum_tdata;
  wire qsum_tlast, qsum_tvalid, qsum_tready;

  // I average
  wire [47:0] iavg_tdata;
  wire iavg_tlast, iavg_tvalid, iavg_tready;
  wire idivisor_tready, idividend_tready;

  // Q average
  wire [47:0] qavg_tdata;
  wire qavg_tlast, qavg_tvalid, qavg_tready;
  wire qdivisor_tready, qdividend_tready;

  //----------------------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------------------

  // Readback register data
  reg [63:0] rb_data;

  //----------------------------------------------------------------------------
  // Instantiations
  //----------------------------------------------------------------------------

  // Set next destination in chain
  setting_reg #(
    .my_addr(SR_NEXT_DST),
    .width(16))
  sr_next_dst(
    .clk(ce_clk),
    .rst(ce_rst),
    .strobe(set_stb),
    .addr(set_addr),
    .in(set_data),
    .out(next_dst),
    .changed());

  // Readback registers
  setting_reg #(
    .my_addr(SR_READBACK),
    .width(1))
  sr_rdback (
    .clk(ce_clk),
    .rst(ce_rst),
    .strobe(set_stb),
    .addr(set_addr),
    .in(set_data),
    .out(rb_addr),
    .changed());

  // Sum length
  setting_reg #(
    .my_addr(SR_SUM_LEN),
    .width(8))
  sr_sum_len (
    .clk(ce_clk),
    .rst(ce_rst),
    .strobe(set_stb),
    .addr(set_addr),
    .in(set_data),
    .out(sum_len),
    .changed(sum_len_changed));

  // Divisor
  setting_reg #(
    .my_addr(SR_DIVISOR),
    .width(24))
  sr_divisor (
    .clk(ce_clk),
    .rst(ce_rst),
    .strobe(set_stb),
    .addr(set_addr),
    .in(set_data),
    .out(divisor),
    .changed());

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE))
  noc_shell_inst (
    .bus_clk(bus_clk),
    .bus_rst(bus_rst),
    .i_tdata(i_tdata),
    .i_tlast(i_tlast),
    .i_tvalid(i_tvalid),
    .i_tready(i_tready),
    .o_tdata(o_tdata),
    .o_tlast(o_tlast),
    .o_tvalid(o_tvalid),
    .o_tready(o_tready),
    // Computer Engine Clock Domain
    .clk(ce_clk),
    .reset(ce_rst),
    // Control Sink
    .set_data(set_data),
    .set_addr(set_addr),
    .set_stb(set_stb),
    .rb_data(rb_data),
    // Control Source
    .cmdout_tdata(64'd0),
    .cmdout_tlast(1'b0),
    .cmdout_tvalid(1'b0),
    .cmdout_tready(),
    .ackin_tdata(),
    .ackin_tlast(),
    .ackin_tvalid(),
    .ackin_tready(1'b1),
    // Stream Sink
    .str_sink_tdata(str_sink_tdata),
    .str_sink_tlast(str_sink_tlast),
    .str_sink_tvalid(str_sink_tvalid),
    .str_sink_tready(str_sink_tready),
    // Stream Source
    .str_src_tdata(str_src_tdata),
    .str_src_tlast(str_src_tlast),
    .str_src_tvalid(str_src_tvalid),
    .str_src_tready(str_src_tready),
    .clear_tx_seqnum(clear_tx_seqnum),
    .debug(debug));

  // AXI Wrapper - Convert RFNoC Shell interface into AXI stream interface
  axi_wrapper #(
    .SR_AXI_CONFIG_BASE(SR_AXI_CONFIG))
  axi_wrapper_inst (
    .clk(ce_clk),
    .reset(ce_rst),
    // RFNoC Shell
    .clear_tx_seqnum(clear_tx_seqnum),
    .next_dst(next_dst),
    .set_stb(set_stb),
    .set_addr(set_addr),
    .set_data(set_data),
    .i_tdata(str_sink_tdata),
    .i_tlast(str_sink_tlast),
    .i_tvalid(str_sink_tvalid),
    .i_tready(str_sink_tready),
    .o_tdata(str_src_tdata),
    .o_tlast(str_src_tlast),
    .o_tvalid(str_src_tvalid),
    .o_tready(str_src_tready),
    // Internal AXI streams
    .m_axis_data_tdata(m_axis_data_tdata),
    .m_axis_data_tuser(m_axis_data_tuser),
    .m_axis_data_tlast(m_axis_data_tlast),
    .m_axis_data_tvalid(m_axis_data_tvalid),
    .m_axis_data_tready(m_axis_data_tready),
    .s_axis_data_tdata(s_axis_data_tdata),
    .s_axis_data_tlast(s_axis_data_tlast),
    .s_axis_data_tvalid(s_axis_data_tvalid),
    .s_axis_data_tready(s_axis_data_tready),
    .m_axis_config_tdata(),
    .m_axis_config_tlast(),
    .m_axis_config_tvalid(),
    .m_axis_config_tready(1'b1));

  // Split incoming data into I and Q parts
  split_complex #(
    .WIDTH(16))
  split_complex_inst (
    .i_tdata(m_axis_data_tdata),
    .i_tlast(m_axis_data_tlast),
    .i_tvalid(m_axis_data_tvalid),
    .i_tready(m_axis_data_tready),
    .oi_tdata(ipart_tdata),
    .oi_tlast(ipart_tlast),
    .oi_tvalid(ipart_tvalid),
    .oi_tready(ipart_tready),
    .oq_tdata(qpart_tdata),
    .oq_tlast(qpart_tlast),
    .oq_tvalid(qpart_tvalid),
    .oq_tready(qpart_tready),
    .error());

  // Accumulate I values
  moving_sum #(
    .MAX_LEN_LOG2(8),
    .WIDTH(16))
  moving_isum_inst (
    .clk(ce_clk),
    .reset(ce_rst),
    .clear(sum_len_changed),
    .len({8'h00, sum_len}),
    .i_tdata(ipart_tdata),
    .i_tlast(ipart_tlast),
    .i_tvalid(ipart_tvalid),
    .i_tready(ipart_tready),
    .o_tdata(isum_tdata),
    .o_tlast(isum_tlast),
    .o_tvalid(isum_tvalid),
    .o_tready(isum_tready));

  // Accumulate Q values
  moving_sum #(
    .MAX_LEN_LOG2(8),
    .WIDTH(16))
  moving_qsum_inst (
    .clk(ce_clk),
    .reset(ce_rst),
    .clear(sum_len_changed),
    .len({8'h00, sum_len}),
    .i_tdata(qpart_tdata),
    .i_tlast(qpart_tlast),
    .i_tvalid(qpart_tvalid),
    .i_tready(qpart_tready),
    .o_tdata(qsum_tdata),
    .o_tlast(qsum_tlast),
    .o_tvalid(qsum_tvalid),
    .o_tready(qsum_tready));

  // Divide I part by divisor from settings register
  divide_int24 divide_i_inst (
    .aclk(ce_clk),
    .aresetn(~ce_rst),
    .s_axis_divisor_tvalid(isum_tvalid),
    .s_axis_divisor_tready(idivisor_tready),
    .s_axis_divisor_tlast(isum_tlast),
    .s_axis_divisor_tdata(divisor),
    .s_axis_dividend_tvalid(isum_tvalid),
    .s_axis_dividend_tready(idividend_tready),
    .s_axis_dividend_tlast(isum_tlast),
    .s_axis_dividend_tdata(isum_tdata),
    .m_axis_dout_tvalid(iavg_tvalid),
    .m_axis_dout_tready(iavg_tready),
    .m_axis_dout_tuser(),
    .m_axis_dout_tlast(iavg_tlast),
    .m_axis_dout_tdata(iavg_tdata));

  // Divide Q part by divisor from settings register
  divide_int24 divide_q_inst (
    .aclk(ce_clk),
    .aresetn(~ce_rst),
    .s_axis_divisor_tvalid(qsum_tvalid),
    .s_axis_divisor_tready(qdivisor_tready),
    .s_axis_divisor_tlast(qsum_tlast),
    .s_axis_divisor_tdata(divisor),
    .s_axis_dividend_tvalid(qsum_tvalid),
    .s_axis_dividend_tready(qdividend_tready),
    .s_axis_dividend_tlast(qsum_tlast),
    .s_axis_dividend_tdata(qsum_tdata),
    .m_axis_dout_tvalid(qavg_tvalid),
    .m_axis_dout_tready(qavg_tready),
    .m_axis_dout_tuser(),
    .m_axis_dout_tlast(qavg_tlast),
    .m_axis_dout_tdata(qavg_tdata));

  // Concatenate I and Q part again
  join_complex #(
    .WIDTH(16))
  join_complex_inst (
    .ii_tdata(iavg_tdata[39:24]), // we only take 16 integer bits
    .ii_tlast(iavg_tlast),
    .ii_tvalid(iavg_tvalid),
    .ii_tready(iavg_tready),
    .iq_tdata(qavg_tdata[39:24]), // we only take 16 integer bits
    .iq_tlast(qavg_tlast),
    .iq_tvalid(qavg_tvalid),
    .iq_tready(qavg_tready),
    .o_tdata(s_axis_data_tdata),
    .o_tlast(s_axis_data_tlast),
    .o_tvalid(s_axis_data_tvalid),
    .o_tready(s_axis_data_tready),
    .error());

  //----------------------------------------------------------------------------
  // Combinational Logic
  //----------------------------------------------------------------------------

  // Make sure dividers are ready
  assign isum_tready = idivisor_tready & idividend_tready;
  assign qsum_tready = qdivisor_tready & qdividend_tready;

  // Readback register values
  always @*
    case(rb_addr)
      1'd0    : rb_data <= sum_len;
      1'd1    : rb_data <= divisor;
      default : rb_data <= 64'h0BADC0DE0BADC0DE;
    endcase

endmodule
