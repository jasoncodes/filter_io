require 'active_support'

class FilterIO
  
  DEFAULT_BLOCK_SIZE = 1024
  
  class NeedMoreData < Exception
  end
  
  class BlockState
    attr_reader :bof, :eof
    def initialize(bof, eof)
      @bof = bof
      @eof = eof
    end
    alias_method :bof?, :bof
    alias_method :eof?, :eof
  end
  
  def initialize(io, options = nil, &block)
    @io = io
    @options = options || {}
    @block = block
    @pos = 0
    @buffer = empty_string
    @options.assert_valid_keys :block_size
  end
  
  def pos
    @pos
  end
  
  def bof?
    @pos == 0
  end
  
  def eof?
    @buffer.empty? && @io.eof?
  end
  
  def readchar
    raise EOFError, 'end of file reached' if eof?
    if @io.respond_to? :external_encoding
      data = empty_string
      begin
        data += read(1).force_encoding(@io.external_encoding)
      end until data.valid_encoding? or @io.eof?
      data
    else
      read(1).ord
    end
  end
  
  def read(length=nil)
    
    # fill the buffer up to the fill level (or whole input if length is nil)
    while !@io.eof? && (length.nil? || length > @buffer.size)
      block_size = @options[:block_size] || length || DEFAULT_BLOCK_SIZE
      data = @io.read(block_size) or break
      begin
        data = process_data data
      rescue NeedMoreData
        raise EOFError, 'end of file reached' if eof?
        data += @io.read(block_size)
        retry
      end
      @buffer += data
    end
    
    # we now have all the data in the buffer that we need (or can get if EOF)
    case
    when @buffer.size > 0
      # limit length to the buffer size if we were asked for it all or have ran out (EOF)
      length = @buffer.size if length.nil? or length > @buffer.size
      @pos += length
      @buffer.slice!(0, length)
    when @io.eof?
      # end of file, nothing in the buffer to return
      length.nil? ? empty_string : nil
    else
      raise IOError, 'Read error'
    end
    
  end
  
  def rewind
    seek 0, IO::SEEK_SET
  end
  
  def seek(offset, whence = IO::SEEK_SET)
    
    new_pos = case whence
    when IO::SEEK_SET
      offset
    when IO::SEEK_CUR
      pos + offset
    when IO::SEEK_END
      raise Errno::EINVAL, 'SEEK_END not supported'
    else
      raise Errno::EINVAL
    end
    
    case new_pos
    when pos
      # noop
    when 0
      @io.rewind
      @pos = 0
      @buffer = empty_string
    else
      raise Errno::EINVAL, 'Random seek not supported'
    end
    
    0
  end
  
  def ungetc(char)
    char = char.chr if char.respond_to? :chr
    @pos -= 1 if @pos > 0
    @buffer = char + @buffer
  end
  
  protected
  
  def empty_string
    str = String.new
    str.force_encoding @io.external_encoding if @io.respond_to?(:external_encoding)
    str
  end
  
  def process_data(data)
    if data && @block
      state = BlockState.new @io.pos == data.length, @io.eof?
      args = [data, state]
      data = @block.call(*args.first(@block.arity))
    end
    data
  end
  
end
