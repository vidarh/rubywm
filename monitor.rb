# Monitor class to represent physical display monitors

module WM
  class Monitor
    attr_reader :id, :width, :height, :xoffset, :yoffset, :geometry, :active_desktop

    def active_desktop=(desktop)
      return if @active_desktop == desktop
      old_desktop = @active_desktop
      @active_desktop = desktop
      if old_desktop&.monitor == self
        old_desktop.monitor = nil
      end
      @active_desktop&.monitor = self
    end
    
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
      "<WM::Monitor name=#{@name} active_desktop=#{@active_desktop&.id} geometry=#{@geometry.inspect}>"
    end
  end
end
