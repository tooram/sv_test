typedef struct{
  bit [3:0] src;
  bit [3:0] dst;
  bit [7:0] data [];
}rt_packet_t;//定义结构体，结构体成员为发送端口，目标端口，发送数据

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
//********************************** stimulator **********************************//
module rt_stimulator(
	rt_interface intf
);
//for debug purpose from waveform	//定义检测状态的变量
  typedef enum {DRV_RESET,DRV_IDLE,DRV_ADDR,DRV_PAD,DRV_DATA} drv_state_t;
  drv_state_t dbg_state;  
  byte unsigned dbg_din_chnl0_data; 
  int src_chnl_status[int];  //关联数组，后面int：src_chnl的number；前面int：dest_chnl的Number ？？
	
//generator传送p给stimulator
  rt_packet_t pkts[$];//定义stimulator中的的队列pkts
  function void put_pkt(input rt_packet_t p);
    pkts.push_back(p);	//将generator中传过来的p放入stimulator的pkts中(在pkts队列尾插入p)
  endfunction

//reset阶段，复位时，reset_n为低电平,frame_n和valid_n为高电平
initial begin : drive_reset_proc 
  drive_reset();
end
task drive_reset();
  @(negedge intf.reset_n);
  dbg_state <= DRV_RESET;
  intf.din <= 0;
  intf.frame_n <= '1;//等效16'hFFFF
  intf.valid_n <= '1;
endtask

// 发送数据
initial begin : drive_chnl_proc
	//rt_packet_t p;
  @(negedge intf.reset_n);
  repeat(10) @(posedge intf.clock);//延迟10个时钟周期
  forever begin	
	automatic rt_packet_t p;//声明一个动态的
	wait(pkts.size()>0);
	p = pkts.pop_front();	//将p从队列pkts里面取出
	fork//后台触发线程，触发线程在后台运行，继续执行剩下内容
		begin	
			wait_src_chnl_avail(p);//判断src chnl是否被占用，是否需要等待
			drive_chnl(p.src, p.dst, p.data);//从P中拿到发送端口，目标端口，发送数据
			set_src_chnl_avail(p);
		end
	join_none
	end
end

task automatic wait_src_chnl_avail(rt_packet_t p);//判断src chnl是否被占用，是否需要等待
	if(!src_chnl_status.exists(p.src))//src_chnl_status关联数组里面不含p.src，(表示未占用任何dest_chnl,一开始不满足）
		src_chnl_status[p.src] = p.dst;//表示当前正在使用src_chnl,对应dest_chnl就是p.dst（p.src端口在向p.dst端口发送数据）
	else if(src_chnl_status[p.src] >= 0)//如果在给0,1,2...dest_chnl发送数据（被占用），需要等待,，否则不需要等待
		wait(src_chnl_status[p.src] == -1);//直到src_chnl_status[p.src] == -1(自定义的dest_chnl端口数之外任意的数，表示未占用任何dest_chnl)
endtask

function automatic set_src_chnl_avail(rt_packet_t p);
	src_chnl_status[p.src] = -1;//如果chnl发送完后，把src_chnl置回来(自定义的dest_chnl端口数之外任意的数，表示未占用任何dest_chnl)
endfunction

task automatic drive_chnl(bit[3:0] saddr, bit [3:0] daddr, byte unsigned data[]);
  $display("@%0t: [DRV]src_chnl[%0d],dest_chnl[%0d] data trans started",$time,saddr,daddr);
	// drive address phase 输入地址位阶段
for(int i=0;i<4;i++)begin  //4 clock
  @(posedge intf.clock);
  dbg_state <=DRV_ADDR;	
  intf.din[saddr] <= daddr[i];
  intf.valid_n[saddr] <= $urandom_range(0,1);	//valid_n在din的地址输入时间段可为任意值x
  intf.frame_n[saddr] <= 1'b0;	//frame_n需要为低
end
	// drive pad phase //隔离阶段
  for (int i=0;i<5;i++)begin  //5 clock
    @(posedge intf.clock);
    dbg_state <=DRV_PAD;
    intf.din[saddr] <= 1'b1;
    intf.valid_n[saddr] <= 1'b1;	//valid_n需为高电平
    intf.frame_n[saddr] <= 1'b0; //frame_n需为低电平
  end
	// drive data phase 传输数据阶段
  foreach(data[id])begin
    for(int i=0;i<8;i++)begin
     @(posedge intf.clock);
      dbg_state <=DRV_DATA;
      dbg_din_chnl0_data <= data[id];
      intf.din[saddr] <= data[id][i];
      intf.valid_n[saddr] <=1'b0;
      intf.frame_n[saddr] <= (id == data.size()-1 && i == 7) ? 1'b1 : 1'b0;//packet最后一位输出数据时frameo_n为高
    end
  end
// drive idle phase 闲置（没有数据传输）阶段
  @(posedge intf.clock);
  dbg_state <=DRV_IDLE;
  dbg_din_chnl0_data <= 0;
  intf.din[saddr] <= 1'b0;
  intf.valid_n[saddr] <= 1'b1;
  intf.frame_n[saddr] <= 1'b1;
  $display("@%0t: [DRV]src_chnl[%0d],dest_chnl[%0d] data trans finished",$time,saddr,daddr);
endtask
endmodule

//********************************** generator **********************************//
module rt_generator;	//generator产生数据交给stimulator
  rt_packet_t pkts[$];	//定义队列

  function void put_pkt(input rt_packet_t p);
    pkts.push_back(p);	//将p放入队列pkts里面（在pkts队列尾插入p）
  endfunction
  
  task get_pkt(output rt_packet_t p);
    wait(pkts.size() >0 )	//队列不为空
      p = pkts.pop_front();	//将p从队列pkts里面取出，提取队列首元素
  endtask

  //generate a random packet
  function void gen_pkt(int src = -1, int dst = -1);
  endfunction
endmodule
//********************************** monitor **********************************//
module rt_monitor(rt_interface intf);
	rt_packet_t in_pkts[16][$];
	rt_packet_t out_pkts[16][$];
	initial begin : mon_chnl_proc
		foreach(in_pkts[i]) begin
			automatic int chid = i;
			fork
			mon_chnl_in(chid);//每个输入端口均调用mon_chnl_in任务，监测数据输入
			mon_chnl_out(chid);//每个输出端口均调用mon_chnl_out任务，监测数据输出
			join_none
		end
	end
	
task automatic mon_chnl_in (bit[3:0]id);//监测数据输入的任务
	rt_packet_t pkt;	//定义结构体变量
	forever begin
	//clear content for the same struct variable。清除pkt
	pkt.data.delete();
	pkt.src = id;	//第id个输入端口
	//monitor specific channel-in data and put it into the queue
	// monitor address phase
	@(negedge intf.frame_n[id]);//监测frame_n下降沿(frame_n由时钟驱动)
		for(int i=0; i<4; i++)begin
		@(negedge intf.clock);		//frame_n下降沿后监测4个clk negedge
		pkt.dst[i]= intf.din[id];
		end
  $display ("@%0t: [MON] src_chn1[%0d] & dest_chn1[%0d] data trans started",$time,pkt.src,pkt.dst);
	//pass pad phase 不考虑pad阶段是否满足协议要求
	repeat(5) @(negedge intf.clock);
	do begin
		pkt.data = new [pkt.data.size + 1](pkt.data);//创建动态数组并复制pkt.data
		for ( int i=0; i<8; i++) begin
			@(negedge intf.clock); //在8个clk negedge监测8bit数据
			pkt.data[pkt.data.size-1][i] = intf.din[id];
		end
	end while(!intf.frame_n[id]);
	in_pkts[id].push_back(pkt);	//将monitor拿到的数据放入in_pkts
	$display("@%0t: [MON] src_chn1[%0d] & dest_chn1[%0d] data trans [%0p] finished",$time,pkt.src,pkt.dst,pkt.data);
	end
endtask

task automatic mon_chnl_out(bit[ 3:0]id);//监测数据输出的任务
	rt_packet_t pkt;
	forever begin
		//clear content for the same struct variable
		pkt.data.delete();
		pkt.src = 0;
		pkt.dst = id;	
		@(negedge intf.frameo_n[id]);
		$display( "@%0t: [MON] CH_OUT dest_chn1[%0d] data trans started",$time,pkt.dst);
		do begin
		pkt.data = new [ pkt.data.size + 1](pkt.data);
		for(int i=0;i<8; i++) begin
			@(negedge intf.clock iff !intf.valido_n[id]);//clock与valido_n信号同时为低
			pkt.data[pkt.data.size-1][i]= intf.dout [id];
		end
	end while(!intf.frameo_n[id]);
	out_pkts[id].push_back(pkt);
	$display("@%0t: [MON] CH_OUT dest_chn1[%0d] data trans [%0p] finished",$time,pkt.dst,pkt.data);
	//monitor specific channel-out data and put it into the queue
	end
endtask

endmodule

//********************************** tb **********************************//
module tb;

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
	
//例化stimulator
rt_stimulator stim(intf);
//例化Monitor
rt_monitor mon(intf);
//例化generator
rt_generator gen();
	
initial begin:generate_data_proc//产生数据
	rt_packet_t p;
	gen.put_pkt('{0,3,'{8'h33,8'h77}});	//调用genarator里面的put_pkt函数
	gen.put_pkt('{0,5,'{8'h55,8'h66}});
	gen.put_pkt('{3,6,'{8'h77,8'h88,8'h22}});
	gen.put_pkt('{4,7,'{8'haa,8'hcc,8'h33}});		
end
initial begin:genarator_to_stimulator_proc//取出genarator中的数据给stimulator
	rt_packet_t p;
	forever begin
		gen.get_pkt(p);
		stim.put_pkt(p);
	end
end

endmodule 
