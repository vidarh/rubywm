class Node
  attr_accessor :split, :nodes, :dir, :parent

  def inspect = "<Node @nodes=#{@nodes.inspect}, @dir=#{@dir.inspect} @split=#{@split.inspect} @parent=#{@parent.object_id}>"
      
  def initialize(nodes=[], parent: nil, dir: nil)
    @nodes = Array(nodes.dup)
    @nodes.each{|n| n.parent = self }
    @parent = parent
    @split = 0.5
    @dir = dir
  end

  # FIXME: Restate children, placements, find in terms of
  # an "each_child"
  def children   = @nodes.map(&:children).flatten.compact
  def placements = @nodes.map(&:placements).flatten.compact

  def find(w)
    @nodes.each do |node|
      n = node.find(w)
      return n if n
    end
    nil
  end

  def keep(k)
    p [:keep, @node]
    @nodes = @nodes.map { |n| n.keep(k) }.compact
    @nodes.each {|n| n.parent = self }
    @nodes.length <= 1 ? @nodes.first : self
  end

  def place(window)
    if @nodes.length < 2
      @nodes << Leaf.new(window, parent: self)
    else
      if @nodes[1].is_a?(Leaf)
        @nodes[1] = Node.new(@nodes[1], parent: self)
      end
      @nodes[1].place(window)
    end
  end


  def layout(geom, gap=GAP, dir = :lr, level = 0)
    @dir ||= dir
    dir = @dir
    nextdir = {lr: :tb, tb: :lr}[dir]
    case @nodes.length
    when 0
    when 1
      g = geom.dup
      if level==0 && @nodes[0].is_a?(Leaf)
        g.width -= 600
        g.x = 300
      end
      @nodes[0].layout(g, dir, level+1)
    when 2
      @nodes[0].layout(split_geom(geom, dir, 0,gap), gap, nextdir, level+1)
      @nodes[1].layout(split_geom(geom, dir, 1,gap), gap, nextdir, level+1)
    else
      STDERR.puts "WARNING: Too many nodes"
    end
  end
end

def Node n, parent: nil
  case n
  when Node then n
  when nil then Node.new(parent:)
  else Node.new(n, parent:)
  end
end
