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
    @buffer_raw = empty_string_raw
    @options.assert_valid_keys :block_size
  end
  
  def pos
    @pos
  end
  
  def bof?
    @pos == 0
  end
  
  def eof?
    @buffer.empty? && source_eof?
  end
  
  def source_eof?
    @buffer_raw.empty? && @io.eof?
  end
  
  def readchar
    raise EOFError, 'end of file reached' if eof?
    if @io.respond_to? :external_encoding
      data = empty_string_raw
      begin
        data << read(1).force_encoding(@io.internal_encoding || @io.external_encoding)
      end until data.valid_encoding? or source_eof?
      data.encode! @io.internal_encoding if @io.internal_encoding
      data
    else
      read(1).ord
    end
  end
  
  def getc
    readchar
  rescue EOFError
    nil
  end
  
  def read(length = nil)
    
    raise ArgumentError if length && length < 0
    return '' if length == 0
    
    # fill the buffer up to the fill level (or whole input if length is nil)
    while !source_eof? && (length.nil? || length > bytesize(@buffer))
      buffer_data @options[:block_size] || length
    end
    
    # we now have all the data in the buffer that we need (or can get if EOF)
    case
    when bytesize(@buffer) > 0
      # limit length to the buffer size if we were asked for it all or have ran out (EOF)
      read_length = if length.nil? or length > bytesize(@buffer)
        bytesize @buffer
      else
        length
      end
      data = pop_bytes read_length
      @pos += bytesize(data)
      if length.nil? && data.respond_to?(:encoding)
        data.force_encoding @io.external_encoding
        data.encode! @io.internal_encoding if @io.internal_encoding
      end
      data
    when source_eof?
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
      @buffer_raw = empty_string_raw
    else
      raise Errno::EINVAL, 'Random seek not supported'
    end
    
    0
  end
  
  def ungetc(char)
    char = char.chr if char.respond_to? :chr
    @pos -= bytesize(char)
    @pos = 0 if @pos < 0
    @buffer = char + @buffer
  end
  
  def gets(sep_string = $/)
    
    return nil if eof?
    return read if sep_string.nil?
    
    paragraph_mode = sep_string == ''
    sep_string = "\n\n" if paragraph_mode
    sep_string = sep_string.to_s unless sep_string.is_a? String
    
    if paragraph_mode
      # consume any leading newlines
      char = getc
      char = getc while char && char.ord == 10
      if char
        ungetc char # push the first non-newline back onto the buffer
      else
        return nil # nothing left except newlines, bail out
      end
    end
    
    # fill the buffer until it contains the separator sequence
    until source_eof? or @buffer.index(sep_string)
      buffer_data
    end
    
    # calculate how much of the buffer to return
    length = if idx = @buffer.index(sep_string)
      # we found the separator, include it in our output
      length = idx + sep_string.size
    else
      # no separator found (must be EOF). return everything we've got
      length = @buffer.size
    end
    
    # increment the position and return the buffer fragment
    data = @buffer.slice!(0, length)
    @pos += bytesize(data)
    
    data
  end
  
  def readline(sep_string = $/)
    gets(sep_string) or raise EOFError, 'end of file reached'
  end
  
  def each_line(sep_string = $/)
    unless block_given?
      klass = defined?(Enumerator) ? Enumerator : Enumerable::Enumerator
      return klass.new(self, :each_line, sep_string)
    end
    while line = gets(sep_string)
      yield line
    end
    self
  end
  alias :each :each_line
  alias :lines :each_line
  
  def readlines(sep_string = $/)
    lines = []
    each_line(sep_string) { |line| lines << line }
    lines
  end
  
  protected
  
  def empty_string
    str = String.new
    if @io.respond_to?(:internal_encoding)
      str.force_encoding @io.internal_encoding || @io.external_encoding
    end
    str
  end
  
  def empty_string_raw
    str = String.new
    if @io.respond_to?(:external_encoding)
      str.force_encoding @io.external_encoding
    end
    str
  end
  
  def bytesize(str)
    str.respond_to?(:bytesize) ? str.bytesize : str.size
  end
  
  def pop_bytes(count)
    data = begin
      if @io.respond_to?(:internal_encoding)
        @buffer.force_encoding 'ASCII-8BIT'
      end
      @buffer.slice!(0, count)
    ensure
      if @io.respond_to?(:internal_encoding)
        @buffer.force_encoding @io.internal_encoding || @io.external_encoding
      end
    end
    data
  end
  
  def buffer_data(block_size = nil)
    
    block_size ||= DEFAULT_BLOCK_SIZE
    
    data = unless @buffer_raw.empty?
     @buffer_raw.slice! 0, bytesize(@buffer_raw)
    else
     @io.read(block_size) or return
    end
    
    initial_data_size = bytesize(data)
    begin
      data = process_data data, initial_data_size
    rescue NeedMoreData => e
      raise EOFError, 'end of file reached' if eof?
      data << @io.read(block_size)
      retry
    end
    
    data = [data] unless data.is_a? Array
    raise 'Block must have 1 or 2 values' unless data.size <= 2
    @buffer << data[0]
    if data[1]
      if @io.respond_to?(:internal_encoding) && @io.internal_encoding
        data[1].convert! @io.external_encoding
      end
      @buffer_raw = data[1]
    end
    
  end
  
  def process_data(data, initial_data_size)
    
    if data.respond_to? :encoding
      org_encoding = data.encoding
      data.force_encoding @io.external_encoding
      additional_data_size = bytesize(data) - initial_data_size
      unless data.valid_encoding? or source_eof? or additional_data_size >= 4
        data.force_encoding org_encoding
        raise NeedMoreData
      end
      data.encode! @io.internal_encoding if @io.internal_encoding
    end
    
    if data && @block
      state = BlockState.new @io.pos == data.length, source_eof?
      args = [data, state]
      args = args.first(@block.arity > 0 ? @block.arity : 1)
      data = @block.call(*args)
    end
    
    data
  end
  
end
