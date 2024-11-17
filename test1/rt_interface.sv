// rt_interface.sv - Router interface definition

interface rt_interface();
  logic clock;
  logic reset_n;
  logic [15:0] din;
  logic [15:0] frame_n;
  logic [15:0] valid_n;
  logic [15:0] dout;
  logic [15:0] valido_n;
  logic [15:0] busy_n;
  logic [15:0] frameo_n;
endinterface
