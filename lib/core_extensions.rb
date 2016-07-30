# https://stackoverflow.com/questions/1489183/colorized-ruby-output
class String
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def highlighted
    return self unless Punch.config.colors_enabled?
    colorize Punch.config.highlight_color_code
  end

  def today_color
    return self unless Punch.config.colors_enabled?
    colorize Punch.config.today_color_code
  end

  def absolute_path
    sub '~', Dir.home
  end
end

class Numeric
  # @return [String]
  def left_pad(args = {})
    char = args.fetch(:with, '0')
    length = args.fetch(:length, 2)
    to_s.rjust length, char
  end
end

class Module
  def flag(*names)
    names.each do |name|
      define_method "#{name}!" do
        instance_variable_set "@#{name}", true
      end
      define_method "#{name}?" do
        instance_variable_get "@#{name}"
      end
    end
  end
end

module Kernel
  def literal(object, indent = "  ")
    case object
    when Hash
      return "{}" if object.empty?
      literal = "{\n"
      object.each do |k, v|
        literal << "#{indent + "  "}#{literal(k)} => "\
          "#{literal(v, (indent + "  "))},\n"
      end
      literal << "#{indent}}"
      literal
    else
      object.inspect
    end
  end

  def yes?(prompt)
    puts "#{prompt} (y|n)"
    Punch.config.in.gets.chomp == 'y'
  end

  def no?(prompt)
    !yes?(prompt)
  end

  def puts(str = "")
    Punch.config.out.puts str
  end

  # Open tempfile and read the content after allowing the
  # user to edit it (like a git commit message).
  def gets_tmp(name, content = '')
    f = Tempfile.new name
    f.write content.to_s
    f.rewind
    system "#{Punch.config.text_editor} #{f.path}"
    f.rewind
    f.read
  ensure
    f.close
  end
end

class Time
  def short_year
    strftime('%y').to_i
  end

  def prev_day
    self - 86_400
  end

  def next_day
    self + 86_400
  end

  # Act like a Block.
  def start
    self
  end

  # Act like a Block.
  def finish
    self
  end
end
