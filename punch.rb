#!/usr/bin/env ruby

# The MIT License (MIT)
#
# Copyright (c) 2015 Rathesan Iyadurai
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/lib"

require 'core_extensions'
require 'config'
require 'brf_parser'
require 'totals'
require 'block'
require 'day'
require 'month'

class PunchClock
  VERSION_NAME = "Hydra Dynamite"

  MIDNIGHT_MADNESS_NOTES = [
    "Get some sleep!",
    "Don't you have any hobbies?",
    "Get some rest, (wo)man...",
    "You should go to bed.",
    "That can't be healthy.",
    "You might need therapy.",
    "All work and no play makes Jack a dull boy.",
    "You need to get your priorities straight.",
    "Work-life balance. Ever heard of it?",
    "Did you know that the average adult needs 7-8 hours of sleep?"
  ]

  # Card names are a restricted form of identifiers.
  CARD_RGX = /^([a-z_][a-zA-Z0-9_]*)$/

  # For easy bash completion export.
  OPTIONS = %w(
    --backup
    --brf
    --card-config
    --cards
    --config
    --config-update
    --config-reset
    --console
    --doc
    --edit
    --engine
    --format
    --github
    --hack
    --help
    --interactive
    --log
    --mail
    --merge
    --next
    --options
    --previous
    --raw
    --stats
    --test
    --trello
    --update
    --version
    --whoami
    --yesterday
  )

  attr_reader :args, :path_to_punch, :month, :month_name, :year, :brf_filepath

  def initialize(args, path_to_punch = __FILE__)
    @args = args
    @path_to_punch = path_to_punch
  end

  def punch_folder
    @punch_folder ||= File.dirname(path_to_punch)
  end

  def hours_folder
    @hours_folder ||= config.hours_folder
  end

  def version
    @version ||= `cd #{punch_folder} && git rev-parse --short HEAD`.chomp
  end

  def last_release
    @last_release ||= `cd #{punch_folder} && git log -1 --format=%cr HEAD`.chomp
  end

  def help_file
    "#{punch_folder}/help.txt"
  end

  def test_file
    "#{punch_folder}/test/punch_test.rb"
  end

  def write!(file)
    file.seek 0, IO::SEEK_SET
    file.truncate 0
    file.write month
    file.seek 0, IO::SEEK_SET
  end

  def hand_in_date
    config.hand_in_date
  end

  def version_name
    VERSION_NAME
  end

  def midnight_madness_notes
    MIDNIGHT_MADNESS_NOTES
  end

  def card_rgx
    CARD_RGX
  end

  def punch
    option = @args.first
    # First argument can be a card.
    if option =~ card_rgx
      Punch.load_card option
      @args.shift
      option = @args.first
    end
    if option == '--options'
      puts OPTIONS.join(" ")
      exit
    end
    if option == '--cards'
      puts config.cards.keys.join(" ")
      exit
    end
    if option == '--card-config'
      puts "  #{literal(config.cards)}"
      exit
    end
    if option == '--brf'
      system "open #{hours_folder}"
      exit
    end
    if option == '-H' || option == '--hack'
      system "cd #{punch_folder} && #{config.text_editor} ."
      exit
    end
    if option == '-h' || option == '--help'
      begin
        require 'tempfile'
        f = Tempfile.new 'help'
        f.write File.readlines(help_file).map { |l|
          l.start_with?('$') ? l.blue : l }.join
        f.seek 0, IO::SEEK_SET
        system "less -R #{f.path}"
      ensure
        f.close
        exit
      end
    end
    if option == '-D' || option == '--doc'
      system "cd #{punch_folder} && yard && open doc/index.html"
      exit
    end
    if option == '-u' || option == '--update'
      puts "Fetching master branch...".pink
      system "cd #{punch_folder} && git pull origin master"
      print_version
      if config.regenerate_punchrc_after_udpate? &&
          File.exist?(config.config_file)
        config.generate_config_file
        puts "Updated ~/.punchrc.".pink
      end
      exit
    end
    if option == '-t' || option == '--test'
      system "#{config.system_ruby} #{test_file}"
      exit
    end
    if option == '-v' || option == '--version'
      print_version
      exit
    end
    if option == '--engine'
      puts "#{RUBY_ENGINE} #{RUBY_VERSION}"
      exit
    end
    if option == '-l' || option == '--log'
      @args.shift
      system "cd #{punch_folder} && #{log(@args.shift)}"
      exit
    end
    if option == '--trello'
      system "open https://trello.com/b/xfN8alsq/punch"
      exit
    end
    if option == '--github'
      system "open https://github.com/rathrio/punch"
      exit
    end
    if option == '--whoami'
      puts "You are the sunshine of my life, #{config.name}.".pink
      exit
    end
    if option == '-c' || option == '--config'
      open_or_generate_config_file
      exit
    end
    if option == '--config-reset'
      if yes? "Are you sure you want to reset ~/.punchrc?"
        config.reset!
        generate_and_open_config_file
      end
      exit
    end
    if option == '--config-update'
      generate_and_open_config_file
      exit
    end
    now = Time.now
    month_nr = now.month
    month_nr = (month_nr + 1) % 12 if now.day > hand_in_date
    if option == '-n' || option == '--next'
      @args.shift
      month_nr = (month_nr + 1) % 12
      option = @args.first
    end
    @year = (month_nr < now.month) ? now.year + 1 : now.year
    if option == '-p' || option == '--previous'
      @args.shift
      month_nr = (month_nr - 1) % 12
      month_nr = 12 if month_nr.zero?
      @year = (month_nr > now.month) ? now.year - 1 : now.year
      option = @args.first
    end
    @month_name = Month.name month_nr
    if option == '-m' || option == '--merge'
      require 'merger'
      @args.shift
      puts Merger.new(@args, month_nr, year).month
      exit
    end
    @brf_filepath = generate_brf_filepath month_name, year
    unless File.exist? brf_filepath
      # Create hours folder if necessary.
      unless File.directory? hours_folder
        if yes? "The directory #{hours_folder.pink} does not exist. Create it?"
          require 'fileutils'
          FileUtils.mkdir_p(hours_folder)
        else
          exit
        end
      end
      # Create empty BRF file for this month.
      File.open(brf_filepath, "w") { |f|
        f.write "#{month_name.capitalize} #{year}" }
    end
    if option == '-b' || option == '--backup'
      @args.shift
      path = @args.shift
      system "cp #{brf_filepath} #{path}"
      exit
    end
    edit_brf if option == '-e' || option == '--edit'
    if option == '-r' || option == '--raw'
      puts raw_brf
      exit
    end
    if option == '--mail'
      require 'brf_mailer'
      mailer = BRFMailer.new(brf_filepath, month_name)
      puts raw_brf
      if yes?("Are you sure you want to mail "\
          "#{mailer.month_name.pink} to #{mailer.receiver.pink}?")
        mailer.deliver
      end
      exit
    end
    File.open brf_filepath, 'r+' do |file|
      @month = Month.build(file.read, month_nr, year)

      if option == '-f' || option == '--format'
        @args.shift
        puts "Before formatting:\n".blue
        puts raw_brf
        @month.cleanup!
        write! file
        puts "\nAfter formatting:\n".blue
        puts raw_brf
        exit
      end
      if option == '-C' || option == '--console'
        require 'pry'; binding.pry
        exit
      end
      if option == '-i' || option == '--interactive'
        @args.shift
        require 'editor'; Editor.new(self).run
        write! file
      end
      if option == '-s' || option == '--stats'
        @args.shift
        require 'stats'
        puts Stats.new(month)
        exit
      end
      unless @args.empty?
        if option == '-d' || option == '--day'
          @args.shift
          date = @args.shift
          unless (day = month.days.find { |d| d.date == date })
            day = Day.new date
            month.add day
          end
        else
          time_to_edit = if (option == '-y' || option == '--yesterday')
            @args.shift
            now.previous_day
          else
            now
          end
          unless (day = month.days.find { |d| d.at? time_to_edit })
            day = Day.new
            day.set time_to_edit
            month.add day
          end
        end
        # Add or remove blocks.
        action = :add
        if @args.first == '--remove'
          @args.shift
          action = :remove
        end
        blocks = @args.map { |block_str| Block.new block_str, day }
        day.send action, *blocks
        if day.unhealthy?
          puts "#{midnight_madness_notes.sample.pink}\n"
        end
        write! file
      end
      # Add today if necessary
      if month.days.none? { |d| d.at? now }
        today = Day.new
        today.set now
        month.add today
      end
      puts month.colored
    end
  rescue BRFParser::ParserError => e
    raise e if config.debug?
    puts "Couldn't parse #{brf_filepath.blue}."
  rescue Interrupt
    puts "\nExiting...".pink
    exit
  rescue => e
    raise e if config.debug?
    puts %{That's not a valid argument, dummy.\nRun #{"punch -h".blue} for help.}
  end

  def config
    Punch.config
  end

  def edit_brf
    open brf_filepath
    exit
  end

  def print_version
    puts "#{version_name.blue} #{version.blue} released #{last_release}"
  end

  def raw_brf
    `cat #{brf_filepath}`
  end

  private

  def generate_brf_filepath(month_name, year)
    "#{hours_folder}/#{month_name}_#{year}.txt"
  end

  def open_or_generate_config_file
    if File.exist? config.config_file
      open config.config_file
    else
      if yes? "The ~/.punchrc file does not exist. Generate it?"
        generate_and_open_config_file
      end
    end
  end

  def generate_and_open_config_file
    config.generate_config_file
    open config.config_file
  end

  def open(file)
    system "#{config.text_editor} #{file}"
  end

  def log(n = nil)
    n = 10 if (n = n.to_i).zero?
    "git log"\
      " --pretty=format:'%C(yellow)%h %Cred%ad %Cblue%an%Cgreen%d %Creset%s'"\
      " --date=short"\
      " -n #{n}"
  end
end

if __FILE__ == $0
  PunchClock.new(ARGV).punch
end
