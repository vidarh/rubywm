
# Public Layout interface

class Layout
  def call(focus=nil) = nil
  def find(window, focus=nil, dir=nil) = nil
  def place(window) = nil
  
  # Update the layout geometry when a monitor changes
  def update_geometry(geom) = nil
    
  def layout(...) = call(...)
end
