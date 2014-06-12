# -*- coding: utf-8 -*-

require 'spec_helper'
require 'stringio'
require 'tempfile'
require 'zlib'
require 'csv'

describe FilterIO do
  def matches_reference_io_behaviour(input)
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
      expect(actual).to eq expected
      if actual.respond_to? :encoding
        expect(actual.encoding).to eq expected.encoding
      end
    end
  end

  it 'works with an empty source' do
    io = FilterIO.new(StringIO.new(''))
    expect(io.bof?).to be_true
    io = FilterIO.new(StringIO.new(''))
    expect(io.eof?).to be_true
    io = FilterIO.new(StringIO.new(''))
    expect {
      io.readchar
    }.to raise_error EOFError
  end

  it 'supports `eof?`' do
    io = FilterIO.new(StringIO.new('x'))
    expect(io.eof?).to be_false
    expect(io.readchar.chr).to eq 'x'
    expect(io.eof?).to be_true
    expect(io.read).to eq ''
    expect(io.read(8)).to eq nil
  end

  it 'supports `bof?`' do
    io = FilterIO.new(StringIO.new('x'))
    expect(io.bof?).to be_true
    expect(io.readchar.chr).to eq 'x'
    expect(io.bof?).to be_false
  end

  it 'can `readchar` with unicode characters' do
    matches_reference_io_behaviour('Résume') { |io| io.readchar }
  end

  it 'can `read` with unicode characters' do
    (1..3).each do |read_size|
      matches_reference_io_behaviour('Résume') { |io| io.read read_size }
    end
  end

  it 'can `read` with unicode characters' do
    matches_reference_io_behaviour('Résume') { |io| io.read }
  end

  it 'can `gets` with unicode characters' do
    matches_reference_io_behaviour("über\nrésumé") { |io| io.gets }
  end

  it 'can filter unicode characters' do
    input = 'Résumé Test'
    expected = 'résumé test'
    [2, nil].each do |block_size|
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) { |data| data.downcase }
      actual = io.read
      expect(actual).to eq expected
    end
  end

  it 'does not buffer forever with bad encoding' do
    input = "123\xc3\xc34567890"
    block_count = 0
    io = FilterIO.new(StringIO.new(input), :block_size => 2) do |data|
      block_count += 1
      expect(data.size).to be <= 6
      data
    end
    actual = io.read
    input.force_encoding 'ASCII-8BIT'
    actual.force_encoding 'ASCII-8BIT'
    expect(actual).to eq input
    expect(block_count).to be >= 3
  end

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

  it 'converts ISO-8859-1 to UTF-8 using `gets`' do
    with_iso8859_1_test_file 'UTF-8' do |io_raw|
      expect(io_raw.readchar).to eq 'ü'
      expect(io_raw.gets).to eq "ber\n"
      str = io_raw.gets
      expect(str.downcase).to eq 'résumé'
      expect(str.encoding.name).to eq 'UTF-8'
    end
  end

  it 'converts ISO-8859-1 to raw using `gets`' do
    with_iso8859_1_test_file nil do |io_raw|
      expect(io_raw.readchar).to eq 'ü'.encode('ISO-8859-1')
      expect(io_raw.gets).to eq "ber\n"
      str = io_raw.gets
      expect(str.downcase).to eq 'résumé'.encode('ISO-8859-1')
      expect(str.encoding.name).to eq 'ISO-8859-1'
    end
  end

  it 'converts ISO-8859-1 to UTF-8 using `readchar`' do
    with_iso8859_1_test_file 'UTF-8' do |io_raw|
      io = FilterIO.new(io_raw)
      "über\n".chars.each do |expected|
        actual = io.readchar
        expect(actual).to eq expected
        expect(actual.encoding.name).to eq 'UTF-8'
      end
    end
  end

  it 'converts ISO-8859-1 to raw using `readchar`' do
    with_iso8859_1_test_file nil do |io_raw|
      io = FilterIO.new(io_raw)
      "über\n".encode('ISO-8859-1').chars.each do |expected|
        actual = io.readchar
        expect(actual).to eq expected
        expect(actual.encoding.name).to eq 'ISO-8859-1'
      end
    end
  end

  it 'converts ISO-8859-1 to UTF-8 using `read`' do
    with_iso8859_1_test_file 'UTF-8' do |io_raw|
      io = FilterIO.new(io_raw)
      expect(io.read(2)).to eq 'ü'.force_encoding('ASCII-8BIT')
      expect(io.read(2).encoding.name).to eq 'ASCII-8BIT'
    end
  end

  it 'converts ISO-8859-1 to raw using `read`' do
    with_iso8859_1_test_file nil do |io_raw|
      io = FilterIO.new(io_raw)
      expect(io.read(1)).to eq 'ü'.encode('ISO-8859-1').force_encoding('ASCII-8BIT')
      expect(io.read(2).encoding.name).to eq 'ASCII-8BIT'
    end
  end

  it 'converts ISO-8859-1 to UTF-8 using `lines`' do
    with_iso8859_1_test_file 'UTF-8' do |io_raw|
      io = FilterIO.new(io_raw)
      expected = ["über\n", 'Résumé']
      actual = io.lines.to_a
      expect(actual).to eq expected
      expect(actual[0].encoding.name).to eq 'UTF-8'
    end
  end

  it 'converts ISO-8859-1 to raw using `lines`' do
    with_iso8859_1_test_file nil do |io_raw|
      io = FilterIO.new(io_raw)
      expected = ["über\n", 'Résumé'].map { |str| str.encode('ISO-8859-1') }
      actual = io.lines.to_a
      expect(actual).to eq expected
      expect(actual[0].encoding.name).to eq 'ISO-8859-1'
    end
  end

  it 'converts ISO-8859-1 to UTF-8 via a block' do
    [1, 2, nil].each do |block_size|
      expected = "über\nrésumé"
      with_iso8859_1_test_file 'UTF-8' do |io_raw|
        io = FilterIO.new(io_raw, :block_size => block_size) do |data, state|
          if state.bof?
            expect(data[0]).to eq 'ü'
          end
          expect(data.encoding.name).to eq 'UTF-8'
          data.downcase
        end
        expect(io.readchar).to eq 'ü'
        expect(io.gets.encoding.name).to eq 'UTF-8'
        expect(io.read(4)).to eq 'rés'.force_encoding('ASCII-8BIT')
        str = io.gets
        expect(str).to eq 'umé'
        expect(str.encoding.name).to eq 'UTF-8'
      end
    end
  end

  it 'converts ISO-8859-1 to raw via a block' do
    [1, 2, nil].each do |block_size|
      expected = "über\nrésumé".encode('ISO-8859-1')
      with_iso8859_1_test_file 'ISO-8859-1' do |io_raw|
        io = FilterIO.new(io_raw, :block_size => block_size) do |data, state|
          if state.bof?
            expect(data[0]).to eq 'ü'.encode('ISO-8859-1')
          end
          expect(data.encoding.name).to eq 'ISO-8859-1'
          data.downcase
        end
        expect(io.readchar).to eq 'ü'.encode('ISO-8859-1')
        expect(io.gets.encoding.name).to eq 'ISO-8859-1'
        expect(io.read(3)).to eq 'rés'.encode('ISO-8859-1').force_encoding('ASCII-8BIT')
        str = io.gets
        expect(str).to eq 'umé'.encode('ISO-8859-1')
        expect(str.encoding.name).to eq 'ISO-8859-1'
      end
    end
  end

  it 'supports reading multibyte characters overlapping block boundaries' do
    input = "\x49\xE2\x99\xA5\x4E\x59\x49\xE2\x99\xA5\x4E\x59".force_encoding('UTF-8')

    io = FilterIO.new(StringIO.new(input), :block_size => 6) do |data, state|
      [data.byteslice(0).force_encoding('UTF-8'), data.byteslice(1..-1).force_encoding('UTF-8')]
    end

    expect(io.read).to eq input
  end

  it 'supports a block returning mix of UTF-8 and ASCII-8BIT' do
    input = "X\xE2\x80\x94Y\xe2\x80\x99"
    input.force_encoding 'ASCII-8BIT'
    io = FilterIO.new(StringIO.new(input), :block_size => 4) do |data, state|
      data.force_encoding data[0] == 'Y' ? 'UTF-8' : 'ASCII-8BIT'
      data
    end
    expect(io.read).to eq input
  end

  it 'supports `read`' do
    input = 'Lorem ipsum dolor sit amet, consectetur adipisicing elit'
    io_reference = StringIO.new(input)
    io = FilterIO.new(StringIO.new(input))
    [10,5,4,8,7,nil,nil].each do |read_len|
      expect(io.read(read_len)).to eq io_reference.read(read_len)
      expect(io.pos).to eq io_reference.pos
      if read_len
        expect(io.readchar).to eq io_reference.readchar
      else
        expect {
          io_reference.readchar
        }.to raise_error EOFError
        expect {
          io.readchar
        }.to raise_error EOFError
      end
      expect(io.pos).to eq io_reference.pos
      expect(io.eof?).to eq io_reference.eof?
    end
    expect(io.read).to eq io_reference.read
    expect(io.read(4)).to eq io_reference.read(4)
    expect(io_reference.eof?).to be_true
    expect(io.eof?).to be_true
  end

  it 'returns empty from read(0) before EOF' do
    io = FilterIO.new(StringIO.new('foo'))
    expect(io.read(0)).to eq ''
    expect(io.pos).to eq 0
    expect(io.eof?).to be_false
  end

  it 'returns empty from read(0) at EOF' do
    io = FilterIO.new(StringIO.new(''))
    expect(io.read(0)).to eq ''
    expect(io.pos).to eq 0
    expect(io.eof?).to be_true
  end

  it 'errors if attempting to read negative' do
    io = FilterIO.new(StringIO.new('foo'))
    expect(io.read(2)).to eq 'fo'
    expect {
      io.read(-1)
    }.to raise_error ArgumentError
    expect(io.pos).to eq 2
  end

  it 'supports reading into user buffer' do
    io = FilterIO.new(StringIO.new('foo bar'))
    buffer = 'abcdef'
    result = io.read(3, buffer)
    expect(result.object_id).to eq buffer.object_id
    expect(buffer).to eq 'foo'
    result = io.read(4, buffer)
    expect(result.object_id).to eq buffer.object_id
    expect(buffer).to eq ' bar'
    result = io.read(3, buffer)
    expect(result).to eq nil
    expect(buffer).to eq ''
  end

  it 'allows filtering of input with a block' do
    input = 'foo bar'
    expected = 'FOO BAR'
    io = FilterIO.new(StringIO.new(input)) do |data|
      data.upcase
    end
    expect(io.read).to eq expected
  end

  it 'passes BOF and EOF state to the block' do
    input = "Test String"
    expected = ">>>*Test** Str**ing*<<<"
    io = FilterIO.new(StringIO.new(input), :block_size => 4) do |data, state|
      data = "*#{data}*"
      data = ">>>#{data}" if state.bof?
      data = "#{data}<<<" if state.eof?
      data
    end
    expect(io.read).to eq expected
  end

  it 'passes a copy of the data to block (to prevent mutation bugs)' do
    input = "foobar"
    expected = [
      ['fo', true],
      ['foob', true],
      ['ar', false],
    ]
    actual = []
    io = FilterIO.new(StringIO.new(input), :block_size => 2) do |data, state|
      actual << [data.dup, state.bof?]
      data.upcase!
      raise FilterIO::NeedMoreData if data == 'FO'
      data
    end
    expect(io.read).to eq input.upcase
    expect(actual).to eq expected
  end

  it 'can be used with Symbol#to_proc' do
    input = 'foo bar'
    expected = 'FOO BAR'
    io = FilterIO.new StringIO.new(input), &:upcase
    expect(io.read).to eq expected
  end

  it 'allows custom block size when used with read(nil)' do
    [1,4,7,9,13,30].each do |block_size|
      input = ('A'..'Z').to_a.join
      expected = input.chars.enum_for(:each_slice, block_size).to_a.map(&:join).map { |x| "[#{x}]" }.join
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data|
        "[#{data}]"
      end
      expect(io.read).to eq expected
    end
  end

  it 'allows custom block size when used with gets/readline' do
    [1,4,7,9,13,30].each do |block_size|
      input = "ABCDEFG\nHJIKLMNOP\n"
      expected = input.chars.enum_for(:each_slice, block_size).to_a.map(&:join).map { |x| "[#{x}]" }.join.lines.to_a
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data|
        "[#{data}]"
      end
      actual = io.readlines
      expect(actual).to eq expected
    end
  end

  it 'allows block size to be different multiple from the input size' do
    (1..5).each do |block_size|
      input_str = ('A'..'Z').to_a.join
      expected_str = input_str.chars.enum_for(:each_slice, block_size).map { |x| "[#{x.join}]" }.join
      (1..5).each do |read_size|
        expected = StringIO.new(expected_str)
        actual = FilterIO.new(StringIO.new(input_str), :block_size => block_size) do |data|
          "[#{data}]"
        end

        until expected.eof?
          expect(actual.read(read_size)).to eq expected.read(read_size)
          expect(actual.pos).to eq expected.pos
        end
        expect(actual.eof?).to eq expected.eof?
      end
    end
  end

  it 'allows the filtered I/O to be rewound' do
    io = FilterIO.new(StringIO.new('foo bar baz'))
    expect(io.read(5)).to eq 'foo b'
    expect(io.read(4)).to eq 'ar b'
    io.rewind
    expect(io.read(3)).to eq 'foo'
    expect(io.readchar.chr).to eq ' '
    io.rewind
    expect(io.readchar.chr).to eq 'f'
    expect(io.read(2)).to eq 'oo'
  end

  it 're-reads from the source when rewound (resets buffer)' do
    str = 'foobar'
    io = FilterIO.new(StringIO.new(str))
    expect(io.read(3)).to eq 'foo'
    str.replace 'FooBar'
    expect(io.read(3)).to eq 'Bar'
    io.rewind
    expect(io.read(3)).to eq 'Foo'
  end

  it 'can be rewound with block' do
    input = 'abcdefghij'
    expected = input[1..-1]
    io = FilterIO.new(StringIO.new(input), :block_size => 4) do |data, state|
      data = data[1..-1] if state.bof?
      data
    end
    expect(io.read(2)).to eq 'bc'
    expect(io.read(4)).to eq 'defg'
    io.rewind
    expect(io.read(2)).to eq 'bc'
    expect(io.read(4)).to eq 'defg'
  end

  it 'supports `ungetc`' do
    input = 'foobar'
    io = FilterIO.new(StringIO.new(input))
    expect(io.read(3)).to eq 'foo'
    io.ungetc 'x'
    io.ungetc 'y'[0].ord
    expect(io.read(3)).to eq 'yxb'
    (1..5).each do |i|
      io.ungetc i.to_s
    end
    expect(io.read).to eq '54321ar'
    expect(input).to eq 'foobar'
  end

  it 'allows block to request more data before processing a block' do
    input = '1ab123456cde78f9ghij0'
    expected = input.gsub(/\d+/, '[\0]')
    (1..5).each do |block_size|
      expected_size = 0
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data, state|
        expected_size += block_size
        raise FilterIO::NeedMoreData if data =~ /\d\z/ && !state.eof?
        unless state.eof?
          expect(data.size).to eq expected_size
        end
        expected_size = 0
        data.gsub(/\d+/, '[\0]')
      end
      expect(io.read).to eq expected
    end
  end

  it 'passes a line ending normalisation example' do
    input = "This\r\nis\r\ra\n\ntest\n\r\n\nstring\r\r\n.\n"
    expected = "This\nis\n\na\n\ntest\n\n\nstring\n\n.\n"
    (1..5).each do |block_size|
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data, state|
        raise FilterIO::NeedMoreData if data =~ /[\r\n]\z/ && !state.eof?
        data.gsub(/\r\n|\r|\n/, "\n")
      end
      expect(io.read).to eq expected
    end
  end

  it 'passes a character dropping example' do
    input = "ab1cde23f1g4hijklmno567pqr8stu9vw0xyz"
    expected = input.gsub(/\d+/, '')
    (1..5).each do |block_size|
      io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data|
        data.gsub(/\d+/, '')
      end
      expect(io.pos).to eq 0
      expect(io.read).to eq expected
      expect(io.pos).to eq expected.size
    end
  end

  it 'supports `getc`' do
    matches_reference_io_behaviour('foo') { |io| io.getc }
  end

  it 'supports `gets` with no args' do
    [
      "",
      "x",
      "foo bar",
      "foo\nbar",
      "foo\nbar\nbaz\n"
    ].each do |input|
      matches_reference_io_behaviour(input) { |io| io.gets }
    end
  end

  it 'supports `gets` for entire content' do
    [
      "",
      "x",
      "foo bar",
      "foo\nbar",
      "foo\nbar\nbaz\n"
    ].each do |input|
      matches_reference_io_behaviour(input) { |io| io.gets(nil) }
    end
  end

  it 'supports `gets` with a separator' do
    [
      "",
      "x",
      "foo\nbar\rbaz\n",
      "abc\rdef\rghi\r",
      "abcxyz",
    ].each do |input|
      ["\r", "x"].each do |sep_string|
        matches_reference_io_behaviour(input) { |io| io.gets(sep_string) }
      end
    end
  end

  it 'supports `get` with a limit' do
    [
      "",
      "x",
      "foo\nbar\rbaz\n",
      "abc\rdef\rghi\r",
      "über",
    ].each do |input|
      [1, 2, 3, 4, 10].each do |limit|
        matches_reference_io_behaviour(input) { |io| io.gets(limit) }
      end
    end
    # TODO: test zero limit
  end

  it 'supports `gets` with a separator and a limit' do
    [
      "",
      "x",
      "foo\nbar\rbaz\n",
      "abc\rdef\rghi\r",
      "über",
    ].each do |input|
      ["\r", "x"].each do |sep_string|
        [1, 2, 3, 4, 10].each do |limit|
          matches_reference_io_behaviour(input) { |io| io.gets(sep_string, limit) }
        end
      end
    end
    # TODO: test zero limit
  end

  it 'errors when `get` is passed more than two args' do
    expect {
      FilterIO.new(StringIO.new).gets(1,2,3)
    }.to raise_error ArgumentError
  end

  it 'supports `gets` with a two character seperator' do
    ["o", "oo"].each do |sep_string|
      matches_reference_io_behaviour("foobarhelloworld") { |io| io.gets(sep_string) }
    end
  end

  it 'supports `gets` when retrieving whole paragraphs' do
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
      expect(actual).to eq expected
    end
  end

  it 'supports `readline`' do
    [
      "foo\nbar\n",
      "foo\nbar\nbaz"
    ].each do |input|
      matches_reference_io_behaviour(input) { |io| io.readline }
      matches_reference_io_behaviour(input) { |io| io.readline("o") }
    end
  end

  it 'supports `readlines`' do
    [
      "foo\nbar\n",
      "foo\nbar\nbaz"
    ].each do |input|
      matches_reference_io_behaviour(input) { |io| io.readlines }
      matches_reference_io_behaviour(input) { |io| io.readlines("o") }
    end
  end

  it 'supports reading lines with both `lines` and `gets`' do
    io = FilterIO.new(StringIO.new("foo\nbar\nbaz"))
    expected = [ ["foo\n", "bar\n"], ["baz", nil] ]
    actual = []
    retval = io.lines do |line|
      actual << [line, io.gets]
    end
    expect(retval).to eq io
    expect(actual).to eq expected
  end

  it 'supports using `lines` as an eumerator' do
    io = FilterIO.new(StringIO.new("foo\nbar\nbaz"))
    e = io.lines
    expected = [ ["foo\n", "bar\n"], ["baz", nil] ]
    actual = e.map { |line| [line, io.gets] }
    expect(actual).to eq expected
  end

  it 'supports `seek` with absolute positions' do
    io = FilterIO.new(StringIO.new("abcdef"))

    # beginning
    expect(io.readchar.chr).to eq 'a'
    expect(io.pos).to eq 1
    io.seek 0, IO::SEEK_SET
    expect(io.readchar.chr).to eq 'a'
    expect(io.pos).to eq 1

    # same position
    io.seek 1, IO::SEEK_SET
    expect(io.readchar.chr).to eq 'b'
    expect(io.pos).to eq 2

    # backwards fail
    expect {
      io.seek 1, IO::SEEK_SET
    }.to raise_error Errno::EINVAL
    expect(io.readchar.chr).to eq 'c'
    expect(io.pos).to eq 3
  end

  it 'supports `seek` with relative positions' do
    io = FilterIO.new(StringIO.new("abcdef"))

    # same pos
    expect(io.read(2)).to eq 'ab'
    expect(io.pos).to eq 2
    io.seek 0, IO::SEEK_CUR
    expect(io.pos).to eq 2

    # backwards fail
    expect(io.read(1)).to eq 'c'
    expect(io.pos).to eq 3
    expect {
      io.seek(-1, IO::SEEK_CUR)
    }.to raise_error Errno::EINVAL
    expect(io.pos).to eq 3

    # forwards fail
    expect(io.pos).to eq 3
    expect {
      io.seek(2, IO::SEEK_CUR)
    }.to raise_error Errno::EINVAL
    expect(io.pos).to eq 3

    # beginning
    io.seek(-io.pos, IO::SEEK_CUR)
    expect(io.pos).to eq 0
  end

  it 'does not support `seek` relative to EOF' do
    io = FilterIO.new(StringIO.new("abcdef"))
    expect {
      io.seek(0, IO::SEEK_END)
    }.to raise_error Errno::EINVAL
    expect {
      io.seek(6, IO::SEEK_END)
    }.to raise_error Errno::EINVAL
    expect {
      io.seek(-6, IO::SEEK_END)
    }.to raise_error Errno::EINVAL
  end

  it 'errors if `seek` is called with invalid whence' do
    io = FilterIO.new(StringIO.new("abcdef"))
    expect {
      io.seek(0, 42)
    }.to raise_error Errno::EINVAL
  end

  it 'raises EOF if block requests more data at EOF' do
    input = "foo"
    [2,3,6].each do |block_size|
      [true, false].each do |always|
        count = 0
        io = FilterIO.new(StringIO.new(input), :block_size => block_size) do |data, state|
          count += 1
          raise FilterIO::NeedMoreData if state.eof? or always
          data
        end
        expect {
          io.readline
        }.to raise_error EOFError
        expected_count = block_size < input.size ? 2 : 1
        expect(count).to eq expected_count
      end
    end
  end

  it 'supports returning unconsumed data from the block' do
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
      expect(io.read).to eq expected
    end
  end

  it 'supports requesting of more data by returning all data as unused' do
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

    expect(actual).to eq expected
    expect(block_count).to be >= 10
  end

  it 'supports `close`' do
    [2, 16].each do |block_size|
      source_io = StringIO.new("foo\nbar\nbaz")
      filtered_io = FilterIO.new(source_io, :block_size => block_size, &:upcase)

      expect(filtered_io.gets).to eq "FOO\n"

      # close the filtered stream
      filtered_io.close

      # both the filtered and source stream should be closed
      expect(source_io).to be_closed
      expect(filtered_io).to be_closed

      # futher reads should raise an error
      expect {
        filtered_io.gets
      }.to raise_error IOError

      # closing again should raise an error
      expect {
        filtered_io.close
      }.to raise_error IOError
    end
  end

  it 'raises an IO error if block returns nil' do
    io = FilterIO.new(StringIO.new("foo")) { |data| nil }
    expect {
      io.read.to_a
    }.to raise_error IOError
  end

  it 'can read from GzipReader stream in raw' do
    input = "über résumé"
    input.force_encoding 'ASCII-8BIT'
    buffer = StringIO.new
    out = Zlib::GzipWriter.new buffer
    out.write input
    out.finish
    buffer.rewind
    io = Zlib::GzipReader.new(buffer, :internal_encoding => 'ASCII-8BIT')

    io = FilterIO.new(io)
    expect(io.readchar).to eq input[0]
    expect(io.readchar).to eq input[1]
    expect(io.read).to eq "ber résumé".force_encoding('ASCII-8BIT')
  end

  it 'can read from GzipReader stream in UTF-8' do
    input = "über résumé"
    buffer = StringIO.new
    out = Zlib::GzipWriter.new buffer
    out.write input
    out.finish
    buffer.rewind
    io = Zlib::GzipReader.new(buffer)

    io = FilterIO.new(io)
    expect(io.readchar).to eq "ü"
    expect(io.readchar).to eq "b"
    expect(io.read).to eq "er résumé"
  end

  it 'supports filtering from a pipe' do
    read_io, write_io = IO::pipe
    write_io.write 'test'
    write_io.close
    io = FilterIO.new read_io do |data|
      data.upcase
    end
    expect(io.read).to eq 'TEST'
  end

  it 'supports IO.copy_stream' do
    input = StringIO.new "Test"
    output = StringIO.new

    filtered_input = FilterIO.new input do |data|
      data.upcase
    end

    IO.copy_stream(filtered_input, output)

    output.rewind
    expect(output.read).to eq 'TEST'
  end

  it 'supports CSV' do
    input = StringIO.new "foo,bar\nbaz"

    filtered_input = FilterIO.new input do |data|
      data.upcase
    end

    rows = []
    CSV.parse(filtered_input) do |row|
      rows << row
    end

    expect(rows).to eq [%w[FOO BAR], %w[BAZ]]
  end
end
