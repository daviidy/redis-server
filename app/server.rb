require "socket"

class YourRedisServer
  def initialize(port)
    @port = port
  end

  def start
    # You can use print statements as follows for debugging, they'll be visible when running tests.
    puts("Logs from your program will appear here!")

    # Uncomment this block to pass the first stage
    server = TCPServer.new(@port)
    # accept ping command
    loop do
      client = server.accept
      command = client.gets
      puts "Received: #{command}"
      if command == "PING\n"
        client.write("+PONG\r\n")
      end
      client.close
    end
  end
end

YourRedisServer.new(6379).start
