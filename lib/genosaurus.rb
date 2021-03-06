require 'rubygems'
require 'mack_ruby_core_extensions'
require 'fileutils'
require 'erb'
require 'yaml'

class Genosaurus

  include FileUtils
  
  class << self
    
    # Instantiates a new Genosaurus, passing the ENV hash as options into it, runs the generate method, and returns the Genosaurus object.
    def run(options = ENV.to_hash)
      gen = self.new(options)
      gen.generate
      gen
    end
    
  end
  
  # Takes any options needed for this generator. If the generator requires any parameters an ArgumentError exception will be
  # raised if those parameters are found in the options Hash. The setup method is called at the end of the initialization.
  def initialize(options = {})
    @options = options
    self.class.required_params.each do |p|
      raise ::ArgumentError.new("The required parameter '#{p.to_s.upcase}' is missing for this generator!") unless param(p)
    end
    @generator_name = self.class.name
    @generator_name_underscore = @generator_name.underscore
    @templates_directory_path = nil
    @manifest_path = nil
    $".each do |f|
      if f.match(/#{@generator_name_underscore}\.rb$/)
        @templates_directory_path = File.join(File.dirname(f), "templates")
        @manifest_path = File.join(File.dirname(f), "manifest.yml")
      end
    end
    setup
  end
  
  # Returns the path to the templates directory.
  # IMPORTANT: The location of the templates_directory_path is VERY important! Genosaurus will attempt to find this location
  # automatically, HOWEVER, if there is a problem, or you want to be special, you can override this method in your generator
  # and have it return the correct path.
  def templates_directory_path
    @templates_directory_path
  end
  
  # Returns the path to the manifest.yml. This is only used if you have a manifest.yml file, if there is no file, or this
  # method returns nil, then an implied manifest is used based on the templates_directory_path contents.
  # IMPORTANT: Genosaurus will attempt to find this location automatically, HOWEVER, if there is a problem, or you want to 
  # be special, you can override this method in your generator and have it return the correct path.
  def manifest_path
    @manifest_path
  end
  
  # To be overridden in subclasses to do any setup work needed by the generator.
  def setup
    # does nothing, unless overridden in subclass.
  end
  
  # To be overridden in subclasses to do work before the generate method is run.
  def before_generate
  end
  
  # To be overridden in subclasses to do work after the generate method is run.
  # This is a simple way to call other generators.
  def after_generate
  end
  
  # Returns the manifest for this generator, which is used by the generate method to do the dirty work.
  # If there is a manifest.yml, defined by the manifest_path method, then the contents of that file are processed
  # with ERB and returned. If there is not manifest.yml then an implied manifest is generated from the contents
  # of the templates_directory_path.
  def manifest
    ivar_cache do 
      if File.exists?(manifest_path)
        # run using the yml file
        template = ERB.new(File.open(manifest_path).read, nil, "->")
        man = YAML.load(template.result(binding))
      else
        files = Dir.glob(File.join(templates_directory_path, "**/*.template"))
        man = {}
        files.each_with_index do |f, i|
          output_path = f.gsub(templates_directory_path, "")
          output_path.gsub!(".template", "")
          output_path.gsub!(/^\//, "")
          man["template_#{i+1}"] = {
            "type" => File.directory?(f) ? "directory" : "file",
            "template_path" => f,
            "output_path" => ERB.new(output_path, nil, "->").result(binding)
          }
        end
      end
      # puts man.inspect
      man
    end
  end
  
  
  # Used to define arguments that are required by the generator.
  def self.require_param(*args)
    required_params << args
    required_params.flatten!
  end
  
  # Returns the required_params array.
  def self.required_params
    @required_params ||= []
  end

  # Returns a parameter from the initial Hash of parameters.
  def param(key)
    (@options[key.to_s.downcase] ||= @options[key.to_s.upcase])
  end

  # Takes an input_file runs it through ERB and 
  # saves it to the specified output_file. If the output_file exists it will
  # be skipped. If you would like to force the writing of the file, use the
  # :force => true option.
  def template(input_file, output_file, options = @options)
    if File.exists?(output_file)
      unless options[:force]
        puts "Skipped: #{output_file}"
        return
      end
    end
    # incase the directory doesn't exist, let's create it.
    directory(File.dirname(output_file))
    # puts "input_file: #{input_file}"
    # puts "output_file: #{output_file}"
    if $genosaurus_output_directory
      output_file = File.join($genosaurus_output_directory, output_file) 
    end
    File.open(output_file, "w") {|f| f.puts ERB.new(File.open(input_file).read, nil, "->").result(binding)}
    puts "Wrote: #{output_file}"
  end
  
  # Creates the specified directory.
  def directory(output_dir, options = @options)
    if $genosaurus_output_directory
      output_dir = File.join($genosaurus_output_directory, output_dir) 
    end
    if File.exists?(output_dir)
      puts "Exists: #{output_dir}"
      return
    end
    mkdir_p(output_dir)
    puts "Created: #{output_dir}"
  end
  
  # This does the dirty work of generation.
  def generate
    generate_callbacks do
      manifest.each_value do |info|
        case info["type"]
        when "file"
          template(info["template_path"], info["output_path"])
        when "directory"
          directory(info["output_path"])
        else
          raise "Unknown 'type': #{info["type"]}!"
        end
      end
    end
  end
  
  private
  def generate_callbacks
    before_generate
    yield
    after_generate
  end
  
end # Genosaurus