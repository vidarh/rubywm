# Monitor class to represent physical display monitors

module WM
  class Monitor
    attr_reader :id, :width, :height, :xoffset, :yoffset, :geometry
    # The monitor is the single source of truth for which desktop it shows;
    # Desktop#monitor is derived from this (see desktop.rb).
    attr_accessor :active_desktop

    def initialize(id, width:, height:, xoffset:, yoffset:)
      @id = id

      @active_desktop = nil
      
      @width   = width
      @height  = height
      @xoffset = xoffset
      @yoffset = yoffset
    
      @geometry = X11::Form::Geometry.new.tap do |g|
        g.x      = xoffset
        g.y      = yoffset
        g.width  = width
        g.height = height
      end.freeze
    end
  
    def inspect
      "<WM::Monitor id=#{@id} active_desktop=#{@active_desktop&.id} geometry=#{@geometry.inspect}>"
    end
  end
end
