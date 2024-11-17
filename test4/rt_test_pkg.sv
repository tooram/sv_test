package rt_test_pkg;

class rt_packet;
  rand bit [3:0] src;
  rand bit [3:0] dst;
  rand bit [7:0] data [];
  constraint pkg_cstr{
	soft data.size inside{[1:32]};
	foreach(data[i])
		soft data[i] == (src << 4) + i;
	}
  function new();
  endfunction
  function void set_members(bit [3:0]src, bit [3:0]dst, bit[7:0]data []);
	this.src = src;
	this.dst = dst;
	this.data = data;
  endfunction
  function string sprint();//打印packet信息的函数
	sprint = {sprint , $sformatf("src = %0d\n",src)};
	sprint = {sprint , $sformatf("dst = %0d\n",dst)};
	sprint = {sprint , $sformatf("data_length = %0d\n",data.size())};
	foreach(data[i])
		sprint = {sprint , $sformatf("data[%0d] = 'h%0x\n", i, data[i])};
  endfunction
  function bit compare(rt_packet p);//输入exp_pkt
		if(dst == p.dst && data == p.data)
			compare = 1;
		else 
			compare = 0;
  endfunction
endclass
//********************************** stimulator **********************************//
class rt_stimulator;
	virtual rt_interface intf;//class里的接口不能用端口的方式描述，需要添加virtual关键字，在类里面用接口的指针
//for debug purpose from waveform	//定义检测状态的变量
  typedef enum {DRV_RESET,DRV_IDLE,DRV_ADDR,DRV_PAD,DRV_DATA} drv_state_t;
  drv_state_t dbg_state;  
  byte unsigned dbg_din_chnl0_data; 
  semaphore src_chnl_status[16];//16个chnl的钥匙
  mailbox #(rt_packet) gen_pkts;
  mailbox #(rt_packet) ch_pkts[16];//从generator收到的数据按照chnl编号分发到16个mailbox里
	
  function new();
  //pkts = new(1);//设定mailbox上限为1
	foreach(src_chnl_status[i])
		src_chnl_status[i] = new(1);
		foreach (ch_pkts[i])
			ch_pkts[i] = new(1);
  endfunction

//generator传送p给stimulator
task run();
	fork
		drive_reset(); //reset动作
		distribute_packets();//分发数据
		get_packet_and_drive(); //drive_chnl动作，发送数据
	join_none
endtask

//分发数据
task distribute_packets();//从generator收到的数据按照chnl编号分发到16个mailbox里
	rt_packet p;
	forever begin
		gen_pkts.get(p);//从stimulator中的mailbox中取出数据
		ch_pkts[p.src].put(p);//将数据写入分发的对应chnl的mailbox中
	end
endtask

task drive_reset();//reset
	forever begin
		@(negedge intf.reset_n);
		dbg_state <= DRV_RESET;
		intf.din <= 0;
		intf.frame_n <= '1;//等效16'hFFFF
		intf.valid_n <= '1;
	end
endtask

// 发送数据
task get_packet_and_drive();
	@(negedge intf.reset_n);
	repeat (10)@(posedge intf.clock);
	foreach(ch_pkts[i])begin
	automatic int id = i;
	automatic rt_packet p;
		fork
			forever begin
			ch_pkts[id].get(p);//从对应chnl的mailbox中取出数据
			drive_chnl(p);//drive数据
			end
		join_none
	end
endtask

task  drive_chnl(rt_packet p);
  $display("@%0t:[DRV] src_chnl[%0d] & dest_chnl[%0d] data trans started with packet: \n%s",$time,p.src,p.dst,p.sprint());
	// drive address phase 输入地址位阶段
for(int i=0;i<4;i++)begin  //4 clock
  @(posedge intf.clock);
  dbg_state <=DRV_ADDR;	
  intf.din[p.src] <= p.dst[i];
  intf.valid_n[p.src] <= $urandom_range(0,1);	//valid_n在din的地址输入时间段可为任意值x
  intf.frame_n[p.src] <= 1'b0;	//frame_n需要为低
end
	// drive pad phase //隔离阶段
  for (int i=0;i<5;i++)begin  //5 clock
    @(posedge intf.clock);
    dbg_state <=DRV_PAD;
    intf.din[p.src] <= 1'b1;
    intf.valid_n[p.src] <= 1'b1;	//valid_n需为高电平
    intf.frame_n[p.src] <= 1'b0; //frame_n需为低电平
  end
	// drive data phase 传输数据阶段
  foreach(p.data[id])begin
    for(int i=0;i<8;i++)begin
     @(posedge intf.clock);
      dbg_state <=DRV_DATA;
      dbg_din_chnl0_data <= p.data[id];
      intf.din[p.src] <= p.data[id][i];
      intf.valid_n[p.src] <=1'b0;
      intf.frame_n[p.src] <= (id == p.data.size()-1 && i == 7) ? 1'b1 : 1'b0;//packet最后一位输出数据时frameo_n为高
    end
  end
// drive idle phase 闲置（没有数据传输）阶段
  @(posedge intf.clock);
  dbg_state <=DRV_IDLE;
  dbg_din_chnl0_data <= 0;
  intf.din[p.src] <= 1'b0;
  intf.valid_n[p.src] <= 1'b1;
  intf.frame_n[p.src] <= 1'b1;
  $display("@%0t: [DRV]src_chnl[%0d],dest_chnl[%0d] data trans finished",$time,p.src,p.dst);
endtask
endclass

//********************************** generator **********************************//
class rt_generator;	//generator产生数据交给stimulator
  mailbox #(rt_packet) pkts;	//定义队列
	
	function new();
		pkts = new(1);//设定mailbox上限为1
	endfunction
	
  task put_pkt(input rt_packet p);
	pkts.put(p);
  endtask
  
  //generate a random packet
  function void gen_pkt(int src = -1, int dst = -1);
  endfunction
  
  task run();
		//TODO
  endtask
	
endclass
//********************************** monitor **********************************//
class rt_monitor;
virtual rt_interface intf;
	rt_packet in_pkts[16][$];
	rt_packet out_pkts[16][$];
	
task run();
	fork
		mon_chnls();
	join_none
endtask
	
task mon_chnls;
	foreach(in_pkts[i]) begin
		automatic int chid = i;
		fork
		mon_chnl_in(chid);//每个输入端口均调用mon_chnl_in任务，监测数据输入
		mon_chnl_out(chid);//每个输出端口均调用mon_chnl_out任务，监测数据输入
		join_none
	end
endtask
	
task  mon_chnl_in (bit[3:0]id);//监测数据输入的任务
	rt_packet pkt;	//定义结构体变量
	forever begin
	//clear content for the same struct variable。清除pkt
	pkt = new();
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
	$display("@%0t:[MON] CH_IN src_chnl[%0d] &dest_chnl[%0d ] finished with packet: \n%s",$time,pkt.src,pkt.dst,pkt.sprint());
	end
endtask

task  mon_chnl_out(bit[ 3:0]id);//监测数据输出的任务
	rt_packet pkt;
	forever begin
		//clear content for the same struct variable
		pkt = new();
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
	// NOTE : src is from data format (user defined)
	pkt.src = pkt.data[0][7:4];//高4位
	out_pkts[id].push_back(pkt);
	$display("@%0t: [MON] CH_OUT dest_chn1[%0d] data finished woth packet : \n %s",$time,pkt.dst,pkt.sprint());
	//monitor specific channel-out data and put it into the queue
	end
endtask

endclass
//********************************** checker **********************************//
class rt_checker;

	int unsigned compare_count;
	int unsigned error_count;
	
	function new();
		compare_count = 0;
		error_count = 0;
	endfunction
	
	rt_packet exp_out_pkts[16][$];
	rt_monitor mon;
	
	task run();
	foreach(exp_out_pkts[i])begin
		automatic int chid = i;
		fork
			do_routing(chid);
			do_compare(chid);
		join_none
		end
	endtask
	
	task do_routing(bit[3:0] id);//将monitor中采样到的输入数据放入期望的输出端队列中
		rt_packet pkt;
		forever begin
			wait(mon.in_pkts[id].size > 0);
			pkt = mon.in_pkts[id].pop_front();//从monitor中拿到in_pkts队列数据放入pkt
			exp_out_pkts[pkt.dst].push_back(pkt);//将pkt数据放入对应期望的dest_chnl
			end
	endtask 
	
	task do_compare(bit[3:0] id);//比较采集的实际输出与期望输出
		rt_packet exp_pkt, act_pkt;
		forever begin
			wait(mon.out_pkts[id].size > 0 && exp_out_pkts[id].size > 0);//实际采样数据与期望数据都有值
			act_pkt = mon.out_pkts[id].pop_front();//实际数据为monitor采样的输出数据
			exp_pkt = exp_out_pkts[id].pop_front();//期望数据为monitor采样到的输入数据
			if(act_pkt.compare(exp_pkt))begin//如果exp_pkt与act_pkt比较成功，返回1
				$display("[CHK] data compare success with packet : \n%s",exp_pkt.sprint());
			end
			else begin
				$display("[CHK] data compare failure with actual packet : \n%s \nexpected packet : \n%s", act_pkt.sprint(), exp_pkt.sprint());
				error_count++;
			end
				compare_count++;
		end
	endtask 
	
	function void report(string name);
		$display("TOTAL COMPARING %0d times",compare_count);
		if(!error_count && check_data_buffer())//判断无误且二者有数据
			$display("TEST [%s] PASSED!",name);
		else begin
			$display("TEST [%s]FAILED!",name);
			$display("TOTAL ERROR %0d times", error_count);
		end
	endfunction
	
	function bit check_data_buffer();
		check_data_buffer = 1;
		foreach(exp_out_pkts[id])begin 
			if(exp_out_pkts[id].size != 0)begin	//exp_out_pkts必须有数据
				check_data_buffer = 0;
				$display("exp_out_pkts[%0d] buffer size is not 0(still with %0d data)",id,exp_out_pkts[id].size);
			end
			if(mon.out_pkts[id].size != 0)begin	//mon.out_pkts必须有数据
				check_data_buffer = 0;
				$display("mon.out_pkts[%0d] buffer size is not 0(still with %0d data)",id,mon.out_pkts[id].size);
			end
		end
	endfunction
	
endclass
//********************************** Optional tests **********************************//
class rt_env;	//rt_env包含各个组件
	rt_stimulator stim;
	rt_monitor mon;
	rt_generator gen;
	rt_checker chk;
		
	function new(virtual rt_interface intf);
		//build stage,例化
		stim = new();
		gen = new();
		mon = new();
		chk = new();
		//connect stage，连接
		stim.intf = intf;
		mon.intf = intf;
		chk.mon = mon;//check拿monitor句柄，即拿monitor中in_pkts与out_pkts队列
		stim.gen_pkts = gen.pkts;//将generaor的句柄赋值给stimlutor，数据从gen传到stim
	endfunction 
	
	task run();
		rt_packet p;
		//run stage，run
		fork
			stim.run();//class里面的函数不会自动调用，需要手动调用
			gen.run();	
			mon.run();
			chk.run();
		join_none	
	endtask
	
	function void report(string name);
		chk.report(name);
	endfunction
	
endclass

class rt_base_test;	//rt_base_test包含rt_env，rt_env包含各个组件
	rt_env env;
	bit gen_trans_done = 0;//表示数据传输未开始
	int unsigned test_drain_time_us = 10;//数据传输完后等待报告的时间
	string name;
	
	function new(virtual rt_interface intf,string name = "rt_base_test");
		env = new(intf);
		this.name = name;
	endfunction
	
	virtual task run();
	$display("TEST %s started",name);
		fork
			env.run();
			report();	//调用report
		join_none
	endtask
	
	task report();
		wait(gen_trans_done == 1);
		#(test_drain_time_us * 1us);
		env.report(name);	//调用env里的chk.report()进行report
		tb.test_intf.report();
		$finish();//terminates the current test
	endtask

  function void set_trans_done(bit done = 1);//将set_trans_done信号置为1，表示数据传输已完成
		gen_trans_done = done;
	endfunction

endclass

	class rt_single_ch_test extends rt_base_test;//单个通道测试
		rand bit signed [4:0] src;
		rand bit signed [4:0] dst;
		rand int unsigned pkt_count =10;
		constraint test_cstr {
			soft pkt_count inside {[20:30]};
			src inside {[0 : 15]};
			dst inside {[0 : 15]};
			}

		function new(virtual rt_interface intf,string name = "rt_single_ch_test");
			super.new(intf,name);
		endfunction
			
		task run();
			rt_packet p;
			super.run();//调用父类的run，即执行env.run()，进行组件的例化等操作
			this.randomize(); //randmoize self to get constrained data
			for ( int cnt=0; cnt < pkt_count; cnt++) begin//随机10次
				p = new( );
				p.randomize() with {src == local::src; dst == local::dst; };
				env.gen.put_pkt(p);
			end
			set_trans_done();
		endtask		
	endclass
	
	class rt_multi_ch_test extends rt_base_test;//多通道测试
		rand int ch_num;
		rand bit [3:0]src[];
		rand bit [3:0]dst[];
		rand int unsigned pkt_count = 10;
		constraint multi_ch_cstr {
			soft pkt_count inside {[5:10]};
			ch_num inside {[1:16]};
			src.size == ch_num;
			dst.size == ch_num;
			foreach(src[i]) src[i] inside {[0:15]};
			foreach(dst[i]) dst[i] inside {[0:15]};
		}
		constraint unique_cstr{
			unique {src};
			unique {dst};
		}//单独声明约束，方便rt_two_ch_same_chout_test里关掉
		
		function new(virtual rt_interface intf,string name = "rt_multi_ch_test");
			super.new(intf,name);
		endfunction
		
		task run();
			rt_packet p;
			super.run();//调用父类的run，即执行env.run()，进行组件的例化等操作
			this.randomize(); //randmoize self to get constrained data
			for ( int cnt=0; cnt < pkt_count; cnt++) begin//随机10次
				foreach (src[i]) begin
					p = new( );
					p.randomize() with {src == local::src[i]; dst == local::dst[i]; };
					env.gen.put_pkt(p);
				end
			end
			set_trans_done();
		endtask	
	endclass
	
	class rt_two_ch_test extends rt_multi_ch_test;
		constraint two_ch_cstr {
				ch_num == 2;//2通道测试
			}
		function new(virtual rt_interface intf,string name = "rt_two_ch_test");
			super.new(intf,name);
		endfunction
	endclass
	
		class rt_two_ch_same_chout_test extends rt_two_ch_test;//子类可以继承父类的run，此处不需要再添加，只需添加约束即可
			rand bit [3:0]same_dst;
			constraint two_ch_same_chout_cstr{
			foreach(dst[i]) dst[i] == same_dst;//保证dst_chnl相同
			same_dst inside {[0:15]};
			unique {src};//随机过程过程中每个src不一样
			}

			function new(virtual rt_interface intf,string name = "rt_two_ch_same_chout_test");
				super.new(intf,name);
				unique_cstr.constraint_mode (0);//关掉父类约束
			endfunction
		endclass



		class rt_full_ch_test extends rt_multi_ch_test;
			constraint full_ch_cstr {
			ch_num == 16;	//通道数量为16
		}
			function new(virtual rt_interface intf,string name = "rt_full_ch_test");
				super.new(intf,name);
			endfunction
		endclass
endpackage
