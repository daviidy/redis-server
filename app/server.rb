require "socket"

class YourRedisServer
  def initialize(port)
    @server = TCPServer.new(port)
    @clients = []
  end

  def start
    loop do
      fds_to_watch = [@server, *@clients]
      puts fds_to_watch
      ready_to_read, _, _ = IO.select(fds_to_watch)
      ready_to_read.each do |fd|
        case fd
        when @server
          accept_client
        else
          handle_client(fd)
        end
      end
    end
  end

  def accept_client
    client = @server.accept
    @clients << client
  end

  def handle_client(client)
    client.readpartial(1024)
    client.write("+PONG\r\n")
  end
end

YourRedisServer.new(6379).start
