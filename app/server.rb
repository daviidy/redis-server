require "socket"

class YourRedisServer
  def initialize(port)
    @server = TCPServer.new(port)
    @clients = []
  end

  def start
    loop do
      fds_to_watch = [@server, *@clients]
      ready_to_read, _, _ = IO.select(fds_to_watch)
      puts "files: " + ready_to_read.length
      ready_to_read.each do |fd|
        case fd
        when @server
          @clients << @server.accept
        else
          handle_client(fd)
        end
      end
    end
  end

  def handle_client(client)
    while line = client.readpartial(1024)
      client.write("+PONG\r\n") if line.include?("ping")
    end
  end
end

YourRedisServer.new(6379).start
