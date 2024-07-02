
# Public Layout interface

class Layout
  def call(focus=nil) = nil
  def find(window, focus=nil, dir=nil) = nil
  def place(window) = nil
    
  def layout(...) = call(...)
end
