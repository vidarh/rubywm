
class Desktop
  attr_accessor :name, :id, :wm, :layout, :window

  def initialize(wm, id, name) = (@wm, @id, @name = wm, id, name)
  def active?  = (@wm.current_desktop_id == self.id)
  def children = @wm.windows.values.find_all{_1.desktop==self}
  def show     = children.each(&:show)
  def hide     = children.each(&:hide)
  def inspect  = "<Desktop id=#{id} window=#{@window}>"

  def update_layout
   (layout&.call if active?)
  end
end


