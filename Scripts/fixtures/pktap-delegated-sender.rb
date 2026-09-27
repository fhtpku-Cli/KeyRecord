#!/usr/bin/env ruby
require 'json'
require 'socket'
require 'timeout'

if ARGV == ['--help']
  puts 'Usage: ruby Scripts/fixtures/pktap-delegated-sender.rb --send TARGET_PID LOOPBACK_PORT'
  puts 'For the separately approved delegated-loopback control only.'
  exit 0
end

result = {kind: 'synthetic-delegated-sender', outcome: 'invalid', sent: 0}
socket = nil
begin
  raise ArgumentError unless ARGV.length == 3 && ARGV[0] == '--send'
  target_pid = Integer(ARGV[1], 10)
  port = Integer(ARGV[2], 10)
  raise ArgumentError unless target_pid.positive? && (1..65_535).cover?(port)
  raise SecurityError unless Process.uid == 0 && Process.euid == 0

  Timeout.timeout(3) do
    socket = UDPSocket.new
    socket.setsockopt(Socket::SOL_SOCKET, 0x1107, [target_pid].pack('i'))
    4.times do
      socket.send('synthetic-control', 0, '127.0.0.1', port)
      result[:sent] += 1
    end
  end
  result[:pid] = Process.pid
  result[:outcome] = 'sent'
rescue StandardError, SecurityError => error
  result[:error_type] = error.class.name
ensure
  socket&.close
  puts JSON.generate(result)
end
exit(result[:outcome] == 'sent' ? 0 : 2)
