-- It's early in boot, so we have plenty of RAM.  Compile
-- the rest of the firmware from source if it's there.
dofile("compileall.lc")

-- telnetd overlay
tcpserv = net.createServer(net.TCP, 120)
tcpserv:listen(23,function(k)
  local telnetd = dofile "telnetd.lc"
  telnetd.on["conn"] = function(k) k(string.format("%s [NODE-%06X]",mqcu,node.chipid())) end
  telnetd.server(k)
end)

print("Startup")
dofile("init3.lc")
