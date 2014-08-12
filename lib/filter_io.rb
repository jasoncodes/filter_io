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
    @source_pos = 0
    @pos = 0
    @buffer = empty_string
    @buffer_raw = empty_string_raw

    invalid_options = @options.keys - [:block_size]
    unless invalid_options.empty?
      raise ArgumentError, "Invalid options: #{invalid_options.join ', '}"
    end
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

  def close
    @io.close
  end

  def closed?
    @io.closed?
  end

  def default_encoding
    unless @default_encoding
      c = @io.getc
      @io.ungetc c
      @default_encoding = c.encoding
    end
    @default_encoding
  end

  def internal_encoding
    if @io.respond_to?(:internal_encoding)
      @io.internal_encoding
    else
      default_encoding
    end
  end

  def external_encoding
    if @io.respond_to?(:external_encoding)
      @io.external_encoding
    else
      default_encoding
    end
  end

  def readchar
    raise EOFError, 'end of file reached' if eof?
    data = empty_string_raw
    begin
      byte = read(1)
      if internal_encoding || external_encoding
        byte.force_encoding internal_encoding || external_encoding
      end
      data << byte
    end until data.valid_encoding? or source_eof?
    data.encode! internal_encoding if internal_encoding
    data
  end

  def getc
    readchar
  rescue EOFError
    nil
  end

  def read(length = nil, buffer = nil)
    raise ArgumentError if length && length < 0
    return '' if length == 0

    # fill the buffer up to the fill level (or whole input if length is nil)
    while !source_eof? && (length.nil? || length > @buffer.bytesize)
      buffer_data @options[:block_size] || length
    end

    # we now have all the data in the buffer that we need (or can get if EOF)
    case
    when @buffer.bytesize > 0
      # limit length to the buffer size if we were asked for it all or have ran out (EOF)
      read_length = if length.nil? or length > @buffer.bytesize
        @buffer.bytesize
      else
        length
      end
      data = pop_bytes read_length, buffer
      @pos += data.bytesize
      if length.nil?
        data.force_encoding external_encoding if external_encoding
        data.encode! internal_encoding if internal_encoding
      end
      data
    when source_eof?
      # end of file, nothing in the buffer to return
      buffer.replace empty_string if buffer
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
      @source_pos = 0
      @pos = 0
      @buffer = empty_string
      @buffer_raw = empty_string_raw
    else
      raise Errno::EINVAL, 'Random seek not supported'
    end

    0
  end

  def ungetc(char)
    char = char.chr
    @pos -= char.bytesize
    @pos = 0 if @pos < 0
    @buffer = char + @buffer
  end

  def gets(*args)
    sep_string, limit = case args.size
    when 0
      [$/, nil]
    when 1
      if args.first.is_a?(Integer)
        [$/, args.first]
      else
        [args.first, nil]
      end
    when 2
      args
    else
      raise ArgumentError
    end

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
    until source_eof? || find_bytes(sep_string) || (limit && @buffer.bytesize >= limit)
      buffer_data @options[:block_size]
    end

    # calculate how much of the buffer to return
    length = if idx = find_bytes(sep_string)
      # we found the separator, include it in our output
      length = idx + sep_string.bytesize
    else
      # no separator found (must be EOF). return everything we've got
      length = @buffer.bytesize
    end
    if limit && length > limit
      length = limit
    end

    # extract the requested number of byte from the buffer
    data = pop_bytes(length).force_encoding(@buffer.encoding)
    # continue retreiving more bytes until we have complete characters
    while limit && !data.valid_encoding? && (@buffer.bytesize > 0 || !source_eof?)
      data += pop_bytes(1).force_encoding(@buffer.encoding)
    end
    # increment the position
    @pos += data.bytesize

    data
  end

  def readline(sep_string = $/)
    gets(sep_string) or raise EOFError, 'end of file reached'
  end

  def each_line(sep_string = $/)
    unless block_given?
      return to_enum(:each_line, sep_string)
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
    if internal_encoding || external_encoding
      str.force_encoding internal_encoding || external_encoding
    end
    str
  end

  def empty_string_raw
    str = String.new
    if external_encoding
      str.force_encoding external_encoding
    end
    str
  end

  def with_byte_buffer
    begin
      org_encoding = @buffer.encoding
      @buffer.force_encoding 'ASCII-8BIT'
      yield
    ensure
      @buffer.force_encoding org_encoding
    end
  end

  def pop_bytes(count, output_buffer = nil)
    with_byte_buffer do
      data = @buffer.slice!(0, count)
      if output_buffer
        output_buffer.replace data
      else
        data
      end
    end
  end

  def find_bytes(str)
    with_byte_buffer do
      @buffer.index(str)
    end
  end

  def buffer_data(block_size = nil)
    block_size ||= DEFAULT_BLOCK_SIZE

    if !@buffer_raw.empty?
     data = @buffer_raw.slice! 0, @buffer_raw.bytesize
    elsif data = @io.read(block_size)
      @source_pos += data.bytesize
      data.force_encoding(external_encoding)
    else
      return
    end

    initial_data_size = data.bytesize
    begin
      data = process_data data, initial_data_size

      # if no processed data was returned and there is unprocessed data...
      if data.is_a?(Array) && data.size == 2 && data[0].size == 0 && data[1].size > 0
        # restore the unprocessed data into the temporary buffer
        data = data[1]
        # and add some more data to the buffer
        raise NeedMoreData
      end
    rescue NeedMoreData => e
      raise EOFError, 'end of file reached' if @io.eof?
      new_data = @io.read(block_size).force_encoding(external_encoding)
      data << new_data
      @source_pos += new_data.bytesize
      retry
    end

    data = [data] unless data.is_a? Array
    raise 'Block must have 1 or 2 values' unless data.size <= 2
    if @buffer.encoding != data[0].encoding
      if [@buffer, data[0]].any? { |x| x.encoding.to_s == 'ASCII-8BIT' }
        data[0] = data[0].dup.force_encoding @buffer.encoding
      end
    end
    @buffer << data[0]
    if data[1]
      if internal_encoding
        data[1].convert! external_encoding
      end
      @buffer_raw = data[1]
    end
  end

  def process_data(data, initial_data_size)
    org_encoding = data.encoding
    data.force_encoding external_encoding if external_encoding
    additional_data_size = data.bytesize - initial_data_size
    unless data.valid_encoding? or source_eof? or additional_data_size >= 4
      data.force_encoding org_encoding
      raise NeedMoreData
    end
    data.encode! internal_encoding if internal_encoding

    if data && @block
      args = [data.dup]
      if @block.arity > 1
        src_pos = begin
          @io.pos
        rescue Errno::ESPIPE
          @source_pos
        end
        args << BlockState.new(src_pos == data.length, source_eof?)
      end
      data = @block.call(*args)
      raise IOError, 'Block returned nil' if data.nil?
    end

    data
  end
end
