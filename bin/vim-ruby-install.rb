#!/usr/bin/env ruby

# vim-ruby-install: install the Vim config files for Ruby editing
#
#  * scope out the target directry and get user to confirm
#    * if no directory found, ask user
#    * allow user to force a search for a Windows gvim installation
#  * find source files from gem or from current directory
#  * copy to target directory, taking account of
#    * line endings (NL for Unix-ish; CRLF for Windows)
#    * permissions (755 for directories; 644 for files)
#

require 'rbconfig'
include Config
require 'fileutils'
require 'optparse'
require 'pathname'

SOURCE_FILES = %w{
  compiler/ruby.vim
  compiler/rubyunit.vim
  ftplugin/ruby.vim
  indent/ruby.vim
  syntax/ruby.vim
}
# XXX: what do we do with 'filetype/filetype.vim' ???
                  

  #
  # Miscelleneous functions in the user's environment.
  #
class Env
    #
    # Returns :UNIX or :WINDOWS, according to CONFIG['host_os'] and $options[:windows].
    #
  def Env.determine_target_os
    os = CONFIG['host_os']
    if os =~ /mswin/ or $options[:windows]
      return :WINDOWS
    else
      return :UNIX
    end
  end

    #
    # Returns the path to the directory where the vim configuration files will be copied from.
    # The first preference is the current directory.  If that fails, we look for the RubyGems
    # package 'vim-ruby'.  Failing that, we return +nil+.
    #
  def Env.determine_source_directory
      # 1. Try the current directory.
    if SOURCE_FILES.all? { |path| FileTest.file?(path) }
      return '.'
      # 2. Try the directory above this installation script.
    elsif SOURCE_FILES.map { |f| File.join(File.dirname($0), '..', f) }.all? { |path| FileTest.file?(path) }
      return File.join(File.dirname($0), '..')
    end
      # 3. Try the gem 'vim-ruby'.
    begin
      require 'rubygems'
      raise "Need RubyGems 0.8+" if Gem::RubyGemsPackageVersion < '0.8'
    rescue LoadError
      return nil
    end
    #vim_ruby_gem_dir = Gem.latest_load_paths.grep(%r{gems/vim-ruby}).last
    vim_ruby_gem_dir = Gem.all_load_paths.grep(%r{gems/vim-ruby}).sort.last
    if vim_ruby_gem_dir
      Dir.chdir(vim_ruby_gem_dir) do
        if SOURCE_FILES.all? { |path| FileTest.file?(path) }
          return vim_ruby_gem_dir
        end
      end
    end
    return nil
  end

  def Env.ask_user(message)
    print message
    gets.strip
  end
end  # class Env


  #
  # A FileWriter writes files with pre-selected line endings and permissions.
  #
  #   writer = FileWriter.new(:UNIX, 0664)
  #   writer.copy(source, target) 
  #
class FileWriter
  LINE_ENDINGS = { :UNIX => "\n", :WINDOWS => "\r\n" }
  
  def initialize(ending, file_permissions=0644, directory_permissions=0755)
    @ending = LINE_ENDINGS[ending] or raise "No/invalid line ending given: #{ending}"
    @permissions = {
      :file => file_permissions,
      :dir  => directory_permissions
    }
  end
    # Source and target paths assumed to be Pathname objects.  Copy the source to the target,
    # ensuring the right line endings.
  def copy(source_path, target_path)
    _ensure_directory_exists(target_path)
    target_path.open('wb', @permissions[:file]) do |io|
      lines = source_path.read.split("\n")
      lines.each do |line|
        io.write(line.chomp + @ending)
      end
    end
    puts "#{source_path.to_s.ljust(25)} -> #{target_path}"
  end
    # Create the given directory with the correct directory permissions.
  def mkpath(directory)
    FileUtils.mkdir_p directory.to_s, :mode => @permissions[:dir], :verbose => true
  end
  def _ensure_directory_exists(path)
    dir = path.dirname
    unless dir.directory?
      mkpath(dir)
    end
  end
end  # class FileWriter


  #
  # Represents the target base directory for installs.  Handles writing the files through a
  # given FileWriter.
  #
class TargetDirectory
  def self.finder
    TargetDirectory::Finder.new
  end
  def initialize(directory, writer)
    @directory = directory  # String
    @writer    = writer     # FileWriter
    @directory = Pathname.new(@directory)
  end
    # Copies the given relative path from the current directory to the target.
  def copy(path)
    source_path = Pathname.new(path)
    target_path = @directory + path
    @writer.copy(source_path, target_path)
  end
  def [](path)
    @directory + path
  end
  def path
    @directory
  end
end  # class TargetDirectory


  #
  # Represents the target directory.  Can find candidates, based on the operating system and
  # user options; but is ultimately created with one in mind.
  #
class TargetDirectory::Finder
  POTENTIAL_DIRECTORIES = {
    :UNIX => [
      "/usr/local/share/vim",
      "/usr/local/vim",
      "/usr/share/vim",
      "/usr/vim",
      "/opt/share/vim",
      "/opt/vim"
    ],
    :WINDOWS => [ File.join(ENV['PROGRAMFILES'], 'vim') ]
  }

    # Guides the user through a selection process, ending in a chosen directory. 
  def find_target_directory
      # 1. Try the potentials (if there are any).
    if dirs = _potential_directories and not dirs.empty?
      puts
      puts "Possible Vim installation directories:"
      dirs.each_with_index do |dir, idx|
        puts "  #{idx+1}) #{dir}"
      end
      puts 
      r = Env.ask_user "Please select one (or anything else to specify another directory): "
      if (1..dirs.size).include? r.to_i
        chosen_directory = dirs[r.to_i - 1]
        return chosen_directory
      end
    end 
      # 2. We didn't find any, or the user wants to enter another.
    if dirs.empty?
      puts
      puts "Couldn't find any Vim installation directories."
    end
    loop do
      dir = Env.ask_user "Please enter the full path to your Vim installation directory: "
      dir = File.expand_path(dir)
      if FileTest.directory?(dir)
        entered_directory = dir
        puts
        return entered_directory
      else
        puts " *** That directory doesn't exist!"
      end
    end
      # 3. We don't get here; every path contains a return statement.
  end
  
 private 

    # Return an array of _potential_ directories (i.e. they exist).  Take the options into
    # account.
  def _potential_directories
    dirs = POTENTIAL_DIRECTORIES[Env.determine_target_os].select { |d| FileTest.directory?(d) }
    dirs.map { |d| _vim_runtime_directory(d) }
  end

    # Given a directory like '/usr/share/vim', returns a directory like '/usr/share/vim/vim63'.
  def _vim_runtime_directory(dir)
    if File.basename(dir) =~ /vim\d+/
      dir
    else
      Dir.glob("#{dir}/vim*").select { |d| d =~ /vim\d+/ }.sort.last
    end
  end

end  # class TargetDirectory::Finder


  #
  # VimRubyInstaller is the class that copies the files from the source directory to the target
  # directory, both of which are provided.  
  #
class VimRubyInstaller

    # +source+ and +target+ are the base directories from and to which the configuration files
    # will be copied.  Both are strings.
  def initialize(source, target)
    @source_dir = source
    unless FileTest.directory?(@source_dir)
      raise "Automatically determined source directory ('#{@source_dir}') doesn't exist"
    end
    unless FileTest.directory?(target)
      raise "Chosen target directory ('#{target}') doesn't exist"
    end
    file_writer = FileWriter.new(Env.determine_target_os)
    @target_dir = TargetDirectory.new(target, file_writer)
  end

    # Since we know the source and target directories, all we have to do is copy the files
    # across.  If the target file is _newer_ than the source file, we make a backup of it and
    # report that to the user.
  def install
    backupdir = BackupDir.new("./vim-ruby-backup.#{Process.pid}")
    Dir.chdir(@source_dir) do
      SOURCE_FILES.each do |path|
        source_path = Pathname.new(path)
        target_path = @target_dir[path]
        if target_path.file? and target_path.mtime > source_path.mtime
            # We're going to overwrite a newer file; back it up, unless they're the same.
          unless _same_contents?(target_path, source_path)
            backupdir.backup(target_path, path)
          end
        end
        @target_dir.copy(path)
      end
    end
    backups = backupdir.contents
    unless backups.empty?
      puts 
      puts "The following backups were made as the files were newer than the ones"
      puts "you were installing:"
      backups.each do |path|
        puts " * #{path}"
      end
      puts
      puts "These backups are located in this directory: #{backupdir.path}"
    end
  end

    # Test two files for equality of contents, ignoring line endings.
  def _same_contents?(p1, p2)
    contents1 = p1.read.split("\n").map { |line| line.chomp }
    contents2 = p2.read.split("\n").map { |line| line.chomp }
    contents1 == contents2
  end

    # A directory for holding backups of configuration files.
  class BackupDir
    def initialize(path)
      @base = Pathname.new(path)
    end
      # Copy basedir/path to @path/path.
    def backup(basedir, path)
      @base.mkpath unless @base.directory?
      source = Pathname.new(basedir) + path
      target = @base + path
      target.dirname.mkpath
      FileUtils.cp(source.to_s, target.to_s)
    end
    def [](path)
      @base + path
    end
    def contents
      return [] unless @base.directory?
      results = []
      Dir.chdir(@base) do
        Pathname.new('.').find do |path|
          results << path if path.file?
        end
      end
      results
    end
    def path
      @base
    end
  end  # class VimRubyInstaller::BackupDir

end  # class VimRubyInstaller

#
#  * * *  M A I N  * * *
#

$options = {
  :windows    => false,
  :target_dir => nil
}

op = OptionParser.new do |p|
  p.banner = %{
     vim-ruby-install.rb: Install the vim-ruby configuration files

      About:
        * Detects the Vim runtime directory
          * User to confirm before proceeding
          * User may specify other directory
        * Takes config files from current directory or from vim-ruby gem
        * Writes files with correct permissions and line endings

      Usage:
        direct:   ruby bin/vim-ruby-install.rb [options]
        gem:      vim-ruby-install.rb [options]

      Options:
  }.gsub(/^    /, '')
  p.on('--windows', 'Install into Windows directories') do
    $options[:windows] = true
  end
  p.on('-d DIR', '--directory', 'Install into given directory') do |dir|
    $options[:target_dir] = dir
  end
  p.on('-h', '--help', 'Show this message') do
    puts p
    exit
  end
  p.on_tail %{
      Notes:

        * "Direct" usage means unpacking a vim-ruby tarball and running this
          program from the vim-ruby directory.

        * The convenient alternative is to use RubyGems:
            gem install vim-ruby
            vim-ruby-install.rb

        * The --windows option is designed for forcing an install into the
          Windows (gvim) configuration directory; useful when running from
          Cygwin or MinGW.
    
        * This installer is quite new (2004-09-20).  Please report bugs to
          gsinclair@soyabea.com.au.
  }.gsub(/^    /, '')
end
op.parse!(ARGV)

source_dir = Env.determine_source_directory
if source_dir.nil? then raise "Can't find source directory"; end
target_dir = $options[:target_dir] || TargetDirectory.finder.find_target_directory
VimRubyInstaller.new(source_dir, target_dir).install

# vim: ft=ruby
