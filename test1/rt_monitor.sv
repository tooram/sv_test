// rt_monitor.sv - Monitor module to observe DUT outputs

module rt_monitor(rt_interface intf);
  rt_packet_t in_pkts[16][$];
  rt_packet_t out_pkts[16][$];

  initial begin : mon_ch_proc
    foreach (in_pkts[i]) begin
      automatic int ch_id = i;
      fork
        monitor_in_ch(ch_id);
        monitor_out_ch(ch_id);
      join_none
    end
  end

  task automatic monitor_in_ch(bit[3:0] id);
    rt_packet_t pkt;
    forever begin
      pkt.data.delete();
      pkt.src_ch = id;
      @(negedge intf.frame_n[id]);
      for (int i = 0; i < 4; i++) begin
        @(negedge intf.clock);
        pkt.dst_ch[i] = intf.din[id];
      end
      $display("@%0t: [MON] src_ch[%0d] & dst_ch[%0d] data trans started", $time, pkt.src_ch, pkt.dst_ch);
      repeat(5) @(negedge intf.clock);
      do begin
        pkt.data = new[pkt.data.size() + 1](pkt.data);
        for (int i = 0; i < 8; i++) begin
          @(negedge intf.clock);
          pkt.data[pkt.data.size() - 1][i] = intf.din[id];
        end
      end while (!intf.frame_n[id]);
      in_pkts[id].push_back(pkt);
      $display("@%0t: [MON] src_ch[%0d] & dst_ch[%0d] data trans [%0p] finished", $time, pkt.src_ch, pkt.dst_ch, pkt.data);
    end
  endtask

  task automatic monitor_out_ch(bit[3:0] id);
    rt_packet_t pkt;
    forever begin
      pkt.data.delete();
      pkt.src_ch = 0;
      pkt.dst_ch = id;
      @(negedge intf.frameo_n[id]);
      $display("@%0t: [MON] CH_OUT dst_ch[%0d] data trans started", $time, pkt.dst_ch);
      do begin
        pkt.data = new[pkt.data.size() + 1](pkt.data);
        for (int i = 0; i < 8; i++) begin
          @(negedge intf.clock iff !intf.valido_n[id]);
          pkt.data[pkt.data.size() - 1][i] = intf.dout[id];
        end
      end while (!intf.frameo_n[id]);
      out_pkts[id].push_back(pkt);
      $display("@%0t: [MON] CH_OUT dst_ch[%0d] data trans [%0p] finished", $time, pkt.dst_ch, pkt.data);
    end
  endtask
endmodule
