require "socket"

class YourRedisServer
  def initialize(port)
    @port = port
  end

  def start
    # You can use print statements as follows for debugging, they'll be visible when running tests.
    puts("Logs from your program will appear here!")

    # Uncomment this block to pass the first stage
    servers = Socket.tcp_server_sockets(@port)
    puts "Server started"
    Socket.accept_loop(servers) do |connection|
      while (line = connection.gets) do
        connection.write("+PONG\r\n") if line.include?('ping')
      end
      connection.close
    end
  end
end

YourRedisServer.new(6379).start
