# -*- coding: utf-8 -*-

require 'test_helper'
require 'stringio'
require 'tempfile'

class FilterIOTest < ActiveSupport::TestCase
  
  def assert_equal_reference_io(input)
    
    expected_io = StringIO.new(input)
    actual_io = FilterIO.new(StringIO.new(input))
    
    results = [expected_io, actual_io].map do |io|
      results = []
      errors = []
      positions = []
      
      # call the block repeatedly until we get to EOF
      # and once more at the end to check what happens at EOF
      one_more_time = [true]
      while !io.eof? || one_more_time.pop
        begin
          results << yield(io)
          errors << nil
        rescue Exception => e
          results << nil
          errors << [e.class, e.message]
        end
        positions << io.pos
        raise 'Too many iterations' if results.size > 100
      end
      
      [results, errors, positions]
    end
    
    # compare the filtered output against the reference
    results[0].zip(results[1]).each do |expected, actual|
      assert_equal expected, actual
    end
    
  end
  
  test "empty source" do
    io = FilterIO.new(StringIO.new(''))
    assert_true io.bof?
    io = FilterIO.new(StringIO.new(''))
    assert_true io.eof?
    io = FilterIO.new(StringIO.new(''))
    assert_raise EOFError do
      io.readchar
    end
  end
  
  test "simple eof" do
    io = FilterIO.new(StringIO.new('x'))
    assert_false io.eof?
    assert_equal 'x', io.readchar.chr
    assert_true io.eof?
    assert_equal '', io.read
    assert_equal nil, io.read(8)
  end
  
  test "simple bof" do
    io = FilterIO.new(StringIO.new('x'))
    assert_true io.bof?
    assert_equal 'x', io.readchar.chr
    assert_false io.bof?
  end
  
  test "unicode readchar" do
    assert_equal_reference_io('Résume') { |io| io.readchar }
  end
  
  test "unicode read" do
    (1..3).each do |read_size|
      assert_equal_reference_io('Résume') { |io| io.read read_size }
    end
  end
  
  test "unicode read all" do
    assert_equal_reference_io('Résume') { |io| io.read }
  end
  
  test "unicode gets" do
    assert_equal_reference_io("über\nrésumé") { |io| io.gets }
  end
  
  test "unicode in block" do
    input = 'Résumé Test'
    expected = 'résumé test'
    [2, nil].each do |block_size|
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) { |data| data.downcase }
      actual = io.read
      assert_equal expected, actual
    end
  end
  
  test "should not buffer forever on bad encoding" do
    input = "123\xc3\xc34567890"
    block_count = 0
    io = FilterIO.new(StringIO.new(input), :block_size => 2) do |data|
      block_count += 1
      assert_operator data.size, :<=, 6
      data
    end
    actual = io.read
    if input.respond_to? :force_encoding
      input.force_encoding 'ASCII-8BIT'
      actual.force_encoding 'ASCII-8BIT'
    end
    assert_equal input, actual
    assert_operator block_count, :>=, 3
  end
  
  if IO.method_defined? :external_encoding
    
    def with_iso8859_1_test_file(internal_encoding)
      Tempfile.open 'filter_io' do |tempfile|
        File.open(tempfile.path, 'wb') do |io|
          io.write "\xFCber\nR\xE9sum\xE9"
        end
        File.open(tempfile.path, :external_encoding => 'ISO-8859-1', :internal_encoding => internal_encoding) do |io|
          yield io
        end
      end
    end
    
    test "ISO-8859-1 sanity check to UTF-8" do
      with_iso8859_1_test_file 'UTF-8' do |io_raw|
        assert_equal 'ü', io_raw.readchar
        assert_equal "ber\n", io_raw.gets
        str = io_raw.gets
        assert_equal 'résumé', str.downcase
        assert_equal 'UTF-8', str.encoding.name
      end
    end
    
    test "ISO-8859-1 sanity check raw" do
      with_iso8859_1_test_file nil do |io_raw|
        assert_equal 'ü'.encode('ISO-8859-1'), io_raw.readchar
        assert_equal "ber\n", io_raw.gets
        str = io_raw.gets
        assert_equal 'résumé'.encode('ISO-8859-1'), str.downcase
        assert_equal 'ISO-8859-1', str.encoding.name
      end
    end
    
    test "iso-8859-1 readchar to UTF-8" do
      with_iso8859_1_test_file 'UTF-8' do |io_raw|
        io = FilterIO.new(io_raw)
        "über\n".chars.each do |expected|
          actual = io.readchar
          assert_equal expected, actual
          assert_equal 'UTF-8', actual.encoding.name
        end
      end
    end
    
    test "iso-8859-1 readchar raw" do
      with_iso8859_1_test_file nil do |io_raw|
        io = FilterIO.new(io_raw)
        "über\n".encode('ISO-8859-1').chars.each do |expected|
          actual = io.readchar
          assert_equal expected, actual
          assert_equal 'ISO-8859-1', actual.encoding.name
        end
      end
    end
    
    test "iso-8859-1 read to UTF-8" do
      with_iso8859_1_test_file 'UTF-8' do |io_raw|
        io = FilterIO.new(io_raw)
        assert_equal 'ü'.force_encoding('ASCII-8BIT'), io.read(2)
        assert_equal 'ASCII-8BIT', io.read(2).encoding.name
      end
    end
    
    test "iso-8859-1 read raw" do
      with_iso8859_1_test_file nil do |io_raw|
        io = FilterIO.new(io_raw)
        assert_equal 'ü'.encode('ISO-8859-1').force_encoding('ASCII-8BIT'), io.read(1)
        assert_equal 'ASCII-8BIT', io.read(2).encoding.name
      end
    end
    
    test "iso-8859-1 lines to UTF-8" do
      with_iso8859_1_test_file 'UTF-8' do |io_raw|
        io = FilterIO.new(io_raw)
        expected = ["über\n", 'Résumé']
        actual = io.lines.to_a
        assert_equal expected, actual
        assert_equal 'UTF-8', actual[0].encoding.name
      end
    end
    
    test "iso-8859-1 lines raw" do
      with_iso8859_1_test_file nil do |io_raw|
        io = FilterIO.new(io_raw)
        expected = ["über\n", 'Résumé'].map { |str| str.encode('ISO-8859-1') }
        actual = io.lines.to_a
        assert_equal expected, actual
        assert_equal 'ISO-8859-1', actual[0].encoding.name
      end
    end
    
    test "iso-8859-1 block to UTF-8" do
      [1, 2, nil].each do |block_size|
        expected = "über\nrésumé"
        with_iso8859_1_test_file 'UTF-8' do |io_raw|
          io = FilterIO.new(io_raw, :block_size => block_size) do |data, state|
            assert_equal 'ü', data[0] if state.bof?
            assert_equal 'UTF-8', data.encoding.name
            data.downcase
          end
          assert_equal 'ü', io.readchar
          assert_equal 'UTF-8', io.gets.encoding.name
          assert_equal 'rés'.force_encoding('ASCII-8BIT'), io.read(4)
          str = io.gets
          assert_equal 'umé', str
          assert_equal 'UTF-8', str.encoding.name
        end
      end
    end
    
    test "iso-8859-1 block raw" do
      [1, 2, nil].each do |block_size|
        expected = "über\nrésumé".encode('ISO-8859-1')
        with_iso8859_1_test_file 'ISO-8859-1' do |io_raw|
          io = FilterIO.new(io_raw, :block_size => block_size) do |data, state|
            assert_equal 'ü'.encode('ISO-8859-1'), data[0] if state.bof?
            assert_equal 'ISO-8859-1', data.encoding.name
            data.downcase
          end
          assert_equal 'ü'.encode('ISO-8859-1'), io.readchar
          assert_equal 'ISO-8859-1', io.gets.encoding.name
          assert_equal 'rés'.encode('ISO-8859-1').force_encoding('ASCII-8BIT'), io.read(3)
          str = io.gets
          assert_equal 'umé'.encode('ISO-8859-1'), str
          assert_equal 'ISO-8859-1', str.encoding.name
        end
      end
    end
    
  end
  
  test "read" do
    input = 'Lorem ipsum dolor sit amet, consectetur adipisicing elit'
    io_reference = StringIO.new(input)
    io = FilterIO.new(StringIO.new(input))
    [10,5,4,8,7,nil,nil].each do |read_len|
      assert_equal io_reference.read(read_len), io.read(read_len)
      assert_equal io_reference.pos, io.pos
      if read_len
        assert_equal io_reference.readchar, io.readchar
      else
        assert_raise(EOFError) { io_reference.readchar }
        assert_raise(EOFError) { io.readchar }
      end
      assert_equal io_reference.pos, io.pos
      assert_equal io_reference.eof?, io.eof?
    end
    assert_equal io_reference.read, io.read
    assert_equal io_reference.read(4), io.read(4)
    assert_true io_reference.eof?
    assert_true io.eof?
  end
  
  test "read zero before eof" do
    io = FilterIO.new(StringIO.new('foo'))
    assert_equal '', io.read(0)
    assert_equal 0, io.pos
    assert_false io.eof?
  end
  
  test "read zero at eof" do
    io = FilterIO.new(StringIO.new(''))
    assert_equal '', io.read(0)
    assert_equal 0, io.pos
    assert_true io.eof?
  end
  
  test "read negative" do
    io = FilterIO.new(StringIO.new('foo'))
    assert_equal 'fo', io.read(2)
    assert_raise ArgumentError do
      io.read(-1)
    end
    assert_equal 2, io.pos
  end
  
  test "simple block" do
    input = 'foo bar'
    expected = 'FOO BAR'
    io = FilterIO.new(StringIO.new(input)) do |data|
      data.upcase
    end
    assert_equal expected, io.read
  end
  
  test "block bof and eof" do
    input = "Test String"
    expected = ">>>*Test** Str**ing*<<<"
    io = FilterIO.new(StringIO.new(input), :block_size => 4) do |data, state|
      data = "*#{data}*"
      data = ">>>#{data}" if state.bof?
      data = "#{data}<<<" if state.eof?
      data
    end
    assert_equal expected, io.read
  end
  
  test "Symbol#to_proc" do
    input = 'foo bar'
    expected = 'FOO BAR'
    io = FilterIO.new StringIO.new(input), &:upcase
    assert_equal expected, io.read
  end
  
  test "block size" do
    [1,4,7,9,13,30].each do |block_size|
      input = ('A'..'Z').to_a.join
      expected = input.chars.enum_for(:each_slice, block_size).to_a.map(&:join).map { |x| "[#{x}]" }.join
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data|
        "[#{data}]"
      end
      assert_equal expected, io.read
    end
  end
  
  test "block size different to read size" do
    (1..5).each do |block_size|
      input_str = ('A'..'Z').to_a.join
      expected_str = input_str.chars.enum_for(:each_slice, block_size).map { |x| "[#{x.join}]" }.join
      (1..5).each do |read_size|
        
        expected = StringIO.new(expected_str)
        actual = FilterIO.new(StringIO.new(input_str), :block_size => block_size) do |data|
          "[#{data}]"
        end
        
        until expected.eof?
          assert_equal expected.read(read_size), actual.read(read_size)
          assert_equal expected.pos, actual.pos
        end
        assert_equal expected.eof?, actual.eof?
        
      end
    end
  end
  
  test "rewind pass through" do
    io = FilterIO.new(StringIO.new('foo bar baz'))
    assert_equal 'foo b', io.read(5)
    assert_equal 'ar b', io.read(4)
    io.rewind
    assert_equal 'foo', io.read(3)
    assert_equal ' ', io.readchar.chr
    io.rewind
    assert_equal 'f', io.readchar.chr
    assert_equal 'oo', io.read(2)
  end
  
  test "rewind resets buffer" do
    str = 'foobar'
    io = FilterIO.new(StringIO.new(str))
    assert_equal 'foo', io.read(3)
    str.replace 'FooBar'
    assert_equal 'Bar', io.read(3)
    io.rewind
    assert_equal 'Foo', io.read(3)
  end
  
  test "rewind with block" do
    input = 'abcdefghij'
    expected = input[1..-1]
    io = FilterIO.new(StringIO.new(input), :block_size => 4) do |data, state|
      data = data[1..-1] if state.bof?
      data
    end
    assert_equal 'bc', io.read(2)
    assert_equal 'defg', io.read(4)
    io.rewind
    assert_equal 'bc', io.read(2)
    assert_equal 'defg', io.read(4)
  end
  
  test "ungetc" do
    input = 'foobar'
    io = FilterIO.new(StringIO.new(input))
    assert_equal 'foo', io.read(3)
    io.ungetc 'x'
    io.ungetc 'y'[0].ord
    assert_equal 'yxb', io.read(3)
    (1..5).each do |i|
      io.ungetc i.to_s
    end
    assert_equal '54321ar', io.read
    assert_equal 'foobar', input
  end
  
  test "need more data" do
    input = '1ab123456cde78f9ghij0'
    expected = input.gsub /\d+/, '[\0]'
    (1..5).each do |block_size|
      expected_size = 0
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data, state|
        expected_size += block_size
        raise FilterIO::NeedMoreData if data =~ /\d\z/ && !state.eof?
        assert_equal expected_size, data.size unless state.eof?
        expected_size = 0
        data.gsub /\d+/, '[\0]'
      end
      assert_equal expected, io.read
    end
  end
  
  test "line ending normalisation" do
    input = "This\r\nis\r\ra\n\ntest\n\r\n\nstring\r\r\n.\n"
    expected = "This\nis\n\na\n\ntest\n\n\nstring\n\n.\n"
    (1..5).each do |block_size|
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data, state|
        raise FilterIO::NeedMoreData if data =~ /[\r\n]\z/ && !state.eof?
        data.gsub /\r\n|\r|\n/, "\n"
      end
      assert_equal expected, io.read
    end
  end
  
  test "dropping characters" do
    input = "ab1cde23f1g4hijklmno567pqr8stu9vw0xyz"
    expected = input.gsub /\d+/, ''
    (1..5).each do |block_size|
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data|
        data.gsub /\d+/, ''
      end
      assert_equal 0, io.pos
      assert_equal expected, io.read
      assert_equal expected.size, io.pos
    end
  end
  
  test "getc" do
    assert_equal_reference_io('foo') { |io| io.getc }
  end
  
  test "gets default" do
    [
      "",
      "x",
      "foo bar",
      "foo\nbar",
      "foo\nbar\nbaz\n"
    ].each do |input|
      assert_equal_reference_io(input) { |io| io.gets }
    end
  end
  
  test "gets all" do
    [
      "",
      "x",
      "foo bar",
      "foo\nbar",
      "foo\nbar\nbaz\n"
    ].each do |input|
      assert_equal_reference_io(input) { |io| io.gets(nil) }
    end
  end
  
  test "gets separator" do
    [
      "",
      "x",
      "foo\nbar\rbaz\n",
      "abc\rdef\rghi\r",
      "abcxyz",
    ].each do |input|
      ["\r", "x"].each do |sep_string|
        assert_equal_reference_io(input) { |io| io.gets(sep_string) }
      end
    end
  end
  
  test "gets 2 char separator" do
    ["o", "oo"].each do |sep_string|
      assert_equal_reference_io("foobarhelloworld") { |io| io.gets(sep_string) }
    end
  end
  
  test "gets paragraph" do
    {
      "" => [],
      "x" => ['x'],
      "foo bar" => ["foo bar"],
      "foo bar\n" => ["foo bar\n"],
      "foo bar\n\n" => ["foo bar\n\n"],
      "foo bar\n\n\n" => ["foo bar\n\n"],
      "foo bar\nbaz" => ["foo bar\nbaz"],
      "foo bar\n\nbaz" => ["foo bar\n\n", "baz"],
      "foo bar\n\n\nbaz" => ["foo bar\n\n", "baz"],
      "foo bar\n\nbaz\n" => ["foo bar\n\n", "baz\n"],
      "foo bar\n\nbaz\n\n" => ["foo bar\n\n", "baz\n\n"],
      "foo bar\n\nbaz\n\n\n" => ["foo bar\n\n", "baz\n\n"],
      "\n\n\nfoo bar\n\nbaz\n\n\nabc\ndef" => ["foo bar\n\n", "baz\n\n", "abc\ndef"],
    }.each do |input, expected|
      io = FilterIO.new(StringIO.new(input))
      actual = []
      while para = io.gets('')
        actual << para
      end
      assert_equal expected, actual
    end
  end
  
  test "readline" do
    [
      "foo\nbar\n",
      "foo\nbar\nbaz"
    ].each do |input|
      assert_equal_reference_io(input) { |io| io.readline }
      assert_equal_reference_io(input) { |io| io.readline("o") }
    end
  end
  
  test "readlines" do
    [
      "foo\nbar\n",
      "foo\nbar\nbaz"
    ].each do |input|
      assert_equal_reference_io(input) { |io| io.readlines }
      assert_equal_reference_io(input) { |io| io.readlines("o") }
    end
  end
  
  test "lines with block" do
    io = FilterIO.new(StringIO.new("foo\nbar\nbaz"))
    expected = [ ["foo\n", "bar\n"], ["baz", nil] ]
    actual = []
    retval = io.lines do |line|
      actual << [line, io.gets]
    end
    assert_equal io, retval
    assert_equal expected, actual
  end
  
  test "lines enumerator" do
    io = FilterIO.new(StringIO.new("foo\nbar\nbaz"))
    e = io.lines
    expected = [ ["foo\n", "bar\n"], ["baz", nil] ]
    actual = e.map { |line| [line, io.gets] }
    assert_equal expected, actual
  end
  
  test "seek set" do
    
    io = FilterIO.new(StringIO.new("abcdef"))
    
    # beginning
    assert_equal 'a', io.readchar.chr
    assert_equal 1, io.pos
    io.seek 0, IO::SEEK_SET
    assert_equal 'a', io.readchar.chr
    assert_equal 1, io.pos
    
    # same position
    io.seek 1, IO::SEEK_SET
    assert_equal 'b', io.readchar.chr
    assert_equal 2, io.pos
    
    # backwards fail
    assert_raise Errno::EINVAL do
      io.seek 1, IO::SEEK_SET
    end
    assert_equal 'c', io.readchar.chr
    assert_equal 3, io.pos
    
  end
    
  test "seek current" do
    
    io = FilterIO.new(StringIO.new("abcdef"))
    
    # same pos
    assert_equal 'ab', io.read(2)
    assert_equal 2, io.pos
    io.seek 0, IO::SEEK_CUR
    assert_equal 2, io.pos
    
    # backwards fail
    assert_equal 'c', io.read(1)
    assert_equal 3, io.pos
    assert_raise Errno::EINVAL do
      io.seek -1, IO::SEEK_CUR
    end
    assert_equal 3, io.pos
    
    # forwards fail
    assert_equal 3, io.pos
    assert_raise Errno::EINVAL do
      io.seek 2, IO::SEEK_CUR
    end
    assert_equal 3, io.pos
    
    # beginning
    io.seek -io.pos, IO::SEEK_CUR
    assert_equal 0, io.pos
    
  end
  
  test "seek end" do
    io = FilterIO.new(StringIO.new("abcdef"))
    assert_raise Errno::EINVAL do
      io.seek 0, IO::SEEK_END
    end
    assert_raise Errno::EINVAL do
      io.seek 6, IO::SEEK_END
    end
    assert_raise Errno::EINVAL do
      io.seek -6, IO::SEEK_END
    end
  end
  
  test "need more data at eof" do
    input = "foo"
    io = FilterIO.new(StringIO.new(input), :block_size => 2) do |data|
      raise FilterIO::NeedMoreData
    end
    assert_raise EOFError do
      io.readline
    end
  end
  
  test "unget via block" do
    # get consecutive unique characters from a feed
    # this is similar to uniq(1) and STL's unique_copy
    input = "122234435"
    expected = "123435"
    (1..5).each do |block_size|
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data, state|
        # grab all of the same character
        data =~ /\A(.)\1*(?!\1)/ or raise 'No data'
        # if there was nothing after it and we aren't at EOF...
        # ...grab more data to make sure we're at the end
        raise FilterIO::NeedMoreData if $'.empty? && !state.eof?
        # return the matched character as data and re-buffer the rest
        [$&[0], $']
      end
      assert_equal expected, io.read
    end
  end
  
  test "get more data via unget" do
    
    input = "foo\ntest\n\n12345\n678"
    expected = input.gsub(/^.*$/) { |x| "#{$&.size} #{$&}" }
    expected += "\n" unless expected =~ /\n\z/
    
    block_count = 0
    io = FilterIO.new StringIO.new(input), :block_size => 2 do |data, state|
      block_count += 1
      raise 'Too many retries' if block_count > 100
      raise "Expected less data: #{data.inspect}" if data.size > 6
      output = ''
      while data =~ /(.*)\n/ || (state.eof? && data =~ /(.+)/)
        output << "#{$1.size} #{$1}\n"
        data = $'
      end
      [output, data]
    end
    actual = io.read
    
    assert_equal expected, actual
    assert_operator block_count, :>=, 10
    
  end
  
end
