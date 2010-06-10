# -*- coding: utf-8 -*-

require 'test_helper'
require 'stringio'

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
    assert_equal_reference_io('Résume') { |io| io.read(2) }
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
  
  test "simple block" do
    input = 'foo bar'
    expected = 'FOO BAR'
    io = FilterIO.new(StringIO.new(input)) do |data|
      data.upcase
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
  
end
