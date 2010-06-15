# `filter_io`
## Filter IO streams with a block. Ruby's FilterInputStream.

`filter_io` is analogous to Java's `FilterIOStream` in that it allows you to intercept and process data in an IO stream. This is particularly useful when cleaning up bad input data for a CSV or XML parser.

`filter_io` provides a one-pass approach to filtering data which can be much faster and memory efficient than doing two passes (cleaning the source file into a buffer and then calling the original parser).

`filter_io` has been tested against Ruby 1.8.7 and Ruby 1.9.2.

### Installation

You can install from Gemcutter by running:

    sudo gem install filter_io

### Example Usage

#### A Simple Example: ROT-13

    io = FilterIO.new io do |data|
      data.tr "A-Za-z", "N-ZA-Mn-za-m"
    end

#### A Useful Example: Line Ending Normalisation

A common usage of `filter_io` is to normalise line endings before parsing CSV data:

    # open source stream
    File.open(filename) do |io|
      
      # apply filter to stream
      io = FilterIO.new(io) do |data, state|
        # grab another chunk if the last character is a delimiter
        raise FilterIO::NeedMoreData if data =~ /[\r\n]\z/ && !state.eof?
        # normalise line endings to LF
        data.gsub /\r\n|\r|\n/, "\n"
      end
      
      # process resulting stream normally
      FasterCSV.parse(io) do |row|
        pp row
      end
      
    end

### Reference

Call `FilterIO.new` with the original IO stream, any options and the filtering block. The returned object pretends like a normal read-only non-seekable IO stream.

#### Block `state` parameter

An optional second parameter to the block is the `state` parameter which contains stream metadata which may be useful when processing the chuck. The methods currently available are:

* `bof?`: Returns true if this is the *first* chuck of the stream.
* `eof?`: Returns true if this is the *last* chunk of the stream.

#### Requesting Additional Data

If the filtering block needs more data to be able to return anything, you can raise a `FilterIO::NeedMoreData` exception and `filter_io` will read another block and pass the additional data to you. This can be repeated as necessary until enough data is retrieved.

For example usage of `NeedMoreData`, see the line ending normalisation example above.

#### Re-buffering Unprocessed Data

If your block is unable to process the whole chunk of data immediately, it can return both the processed chuck and the remainder to be processed later. This is done by returning a 2 element array: `[processed, unprocessed]`. If `processed` is empty and there is `unprocessed` data, `filter_io` will grab another block of data from the source stream and call the block again.

Here's an example which processes whole lines and prepends the line length to the beginning of each line.

    io = FilterIO.new io do |data, state|
      output = ''
      # grab complete lines until we hit EOF
      while data =~ /(.*)\n/ || (state.eof? && data =~ /(.+)/)
        output << "#{$1.size} #{$1}\n"
        data = $'
      end
      # `output` contains the processed lines, `data` contains any left over partial line
      [output, data]
    end

#### Block Size

When either `readline`, `gets` or `read(nil)` is called, `filter_io` will process the input stream in 1,024 byte chucks. You can adjust this by passing a `:block_size` option to `new`.

#### Character Encodings

Ruby 1.9 has character encoding support can convert between UTF-8, ISO-8859-1, ASCII-8BIT, etc. This is triggered in `IO` by using `:external_encoding` and `:internal_encoding` when opening the stream.
`filter_io` will use the underlying stream's encoding settings when reading and filtering data. The processing block will be passed data in the internal encoding.
As per the core `IO` object, if `read` is called with a length (in bytes), the data will be returned in the external encoding.
In summary, everything should Just Work&trade;

### Note on Patches/Pull Requests
 
* Fork the project.
* Make your feature addition or bug fix.
* Add tests for it. This is important so I don't break it in a
  future version unintentionally.
* Commit, do not mess with rakefile, version, or history.
  (if you want to have your own version, that is fine but bump version in a commit by itself I can ignore when I pull)
* Send me a pull request. Bonus points for topic branches.

### Copyright

Copyright (c) 2010 Jason Weathered. See LICENSE for details.
