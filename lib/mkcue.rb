# -*- coding: utf-8 -*-
require 'open-uri'

MustSpecifyEmailAddress = Class.new(ArgumentError)
MustInsertCDtoDrive = Class.new(StandardError)

class MkCue
  DEFAULT_OPTIONS = {
    :device => '/dev/cdrom', 
    :freedb => 'http://freedbtest.dyndns.org/~cddb/cddb.cgi'
  }

  attr_reader :options, :disc_id, :host_name, :q_genre, :cue_sheet

  def initialize(options = {})
    @options = DEFAULT_OPTIONS.update(options)
    raise MustSpecifyEmailAddress if options[:email].nil?

    @disc_id, status = `cd-discid #{options[:device]}`.split(/\s/), $?
    @cue_sheet, status = `mkcue #{options[:devise]}`, $?
    raise MustInsertCDtoDrive unless status.success?

    @host_name = `hostname`.chomp
    @cddb = get_cddb
    update_cuesheet(@cue_sheet)
    @cue_sheet.encode!(Encoding::Windows_31J)
  end

  def query_command
    "#{options[:freedb]}?cmd=cddb+query+#{disc_id.join('+')}" +
      "&hello=#{options[:email]}+#{host_name}+#{__FILE__}+1.0&proto=6"
  end

  def read_command
    "#{options[:freedb]}?cmd=cddb+read+#{q_genre}+#{disc_id[0]}" +
      "&hello=#{options[:email]}+#{host_name}+#{__FILE__}+1.0&proto=6"
  end

  def found(info)
    status, @q_genre = info.readline.match(/^(\d{3})\s+([^\s]+)/).captures
    status == "200"
  end

  def get_cddb
    open(query_command) do |info| 
      found(info) ? open(read_command).readline(nil) : ""
    end
  end

  def year
    @cddb[/^DYEAR=(\d{4})/, 1] || ""
  end
  def discid
    @cddb[/^DISCID=(\w{8})/, 1] || ""
  end
  def genre
    @cddb[/^DGENRE=(.+)\r$/, 1] || ""
  end
  def album_artist
    escape_quote( (@cddb[%r!^DTITLE=([^/]+)/(.+)\r$!, 1] || "").strip )
  end
  def album_title
    escape_quote( (@cddb[%r!^DTITLE=([^/]+)/(.+)\r$!, 2] || "").strip )
  end
  def track_artist(n)
    escape_quote( @cddb[%r!^TTITLE#{n}=([^/]*\S)\s*/(.*\S)\s*\r$!, 1] || "" )
  end
  def track_title(n)
    escape_quote (
      if track_artist(n).empty?
        (@cddb[%r!^TTITLE#{n}=(.+)\r$!, 1] || "").strip
      else
        (@cddb[%r!^TTITLE#{n}=([^/]+)/(.+)\r$!, 2] || "").strip
      end
    )
  end

  def update_cuesheet(cue_sheet)
    set_header(cue_sheet)
    cue_sheet.gsub!('"dummy.wav"', '"CDImage.wav"')
    cue_sheet.gsub!(%r!  TRACK (\d{2}) AUDIO\n    INDEX (\d{2}) (\d{2}:\d{2}:\d{2})!) do |track|
      track_no = $1.to_i - 1
<<TRACK
  TRACK #$1 AUDIO
    TITLE "#{track_title(track_no)}"
    PERFORMER "#{track_artist(track_no).empty? ? album_artist : track_artist(track_no)}"
    INDEX #$2 #$3
TRACK
.chomp
    end

  end

  def set_header(cue_sheet)
    header = <<HEADER
REM GENRE #{genre.upcase}
REM DATE #{year}
REM DISCID #{discid.upcase}
PERFORMER "#{album_artist}"
TITLE "#{album_title}"
HEADER
    cue_sheet.replace(header + cue_sheet)
  end

  def escape_quote(str)
    is_open = false
    str.each_char.map do |c|
      if c == "\""
        is_open = !is_open
        is_open ? "“" : "”"
      else
        c
      end
    end.join
  end
end
