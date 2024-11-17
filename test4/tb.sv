//********************************** rt_interface **********************************//
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

//********************************** tb **********************************//
module tb;

  import rt_test_pkg ::*;
	
	bit clk,rstn;
	logic [15:0] din, frame_n, valid_n;
	logic [15:0] dout, valido_n, busy_n, frameo_n;

// 产生时钟，周期为10ns
initial 
    forever #5ns clk <= !clk;

// 产生复位信号
  initial begin
    #2ns rstn <= 1;
    #10ns rstn <= 0;
    #10ns rstn <= 1;
  end

router_io test_intf(clk);
    assign test_intf.reset_n = rstn;
    assign test_intf.din = intf.din;
    assign test_intf.dout = intf.dout;
    assign test_intf.frame_n = intf.frame_n;
    assign test_intf.valid_n = intf.valid_n;
    assign test_intf.frameo_n = intf.frameo_n;
    assign test_intf.busy_n = intf.busy_n;

//例化router为DUT
router dut(           
  .reset_n(rstn),
  .clock(clk),
  .frame_n(intf.frame_n),
  .valid_n(intf.valid_n),
  .din(intf.din),
  .dout(intf.dout),
  .busy_n(intf.busy_n),
  .valido_n(intf.valido_n),
  .frameo_n(intf.frameo_n)
);

rt_interface intf();//例化接口
	assign intf.reset_n = rstn;
	assign intf.clock = clk;

	rt_single_ch_test  single_ch_test;
	rt_two_ch_test   two_ch_test;
	rt_multi_ch_test   multi_ch_test;
	rt_two_ch_same_chout_test two_ch_same_chout_test;
	rt_full_ch_test full_ch_test;
	
	rt_base_test tests[string];//父类记得添加virtual，否则存放的是父类句柄，执行父类的run
	
	initial begin : Select_the_test
		string name;
		single_ch_test = new(intf);
		two_ch_test  = new(intf);
		multi_ch_test  = new(intf);
		two_ch_same_chout_test  = new(intf);
		full_ch_test  = new(intf);
		
		tests["rt_single_ch_test"] = single_ch_test;
		tests["rt_two_ch_test"   ] = two_ch_test;
		tests["rt_multi_ch_test" ] = multi_ch_test ;
		tests["rt_two_ch_same_chout_test"] = two_ch_same_chout_test;
		tests["rt_full_ch_test"] = full_ch_test;
		
		if($value$plusargs("TESTNAME=%s",name))begin//$value$plusargs作用：运行仿真时输入参数
			if(tests.exists(name))
        tests[name].run();//调用对应test进行run
			else
				$fatal("[ERRTEST],test name %s is invalid,please specity a valid name!0",name);
			end
    end
	
endmodule 
