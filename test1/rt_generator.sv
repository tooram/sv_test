// rt_generator.sv - Data generator module for stimulus packets

module rt_generator;
  rt_packet_t pkts_q[$];

  function void put_pkt(input rt_packet_t pkt);
    pkts_q.push_back(pkt);
  endfunction

  task get_pkt(output rt_packet_t pkt);
    wait(pkts_q.size() > 0);
    pkt = pkts_q.pop_front();
  endtask
endmodule
