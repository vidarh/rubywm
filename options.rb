# Minimal CLI option parsing for rubywm, kept separate so it can be unit-tested
# without starting the window manager.
module Options
  FLAGS = {
    "--drb"   => :drb,   # start the DRb service for remote control/debugging
    "--debug" => :debug, # open an IRB session in a background thread
  }.freeze

  def self.parse(argv)
    opts = FLAGS.values.to_h { |k| [k, false] }
    argv.each do |arg|
      key = FLAGS[arg] or raise ArgumentError, "unknown option: #{arg}"
      opts[key] = true
    end
    opts
  end
end
