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
    @clients << @server.accept
  end

  def handle_client(client)
    while line = client.gets
      p 'line: ', line
      client.write("+PONG\r\n") if line === "ping"
    end
    client.close
  end
end

YourRedisServer.new(6379).start
