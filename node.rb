class Node
  attr_accessor :ratio, :nodes, :dir, :parent
  attr_reader :geom

  def inspect = "<Node #{object_id} @nodes=#{@nodes.inspect}, @dir=#{@dir.inspect} @ratio=#{@ratio.inspect} @parent=#{@parent.object_id}>"
      
  def initialize(nodes=[], parent: nil, dir: nil)
    @nodes = Array(nodes.dup)
    @nodes.each{|n| n.parent = self }
    @parent = parent
    @ratio = 0.5
    @dir = dir
    @geom = nil # *current* geometry, subject to change at all time
  end

  def children   = @nodes.map(&:children).flatten.compact
  def placements = @nodes.map(&:placements).flatten.compact

  def find(w)
    @nodes.each do
      n = _1.find(w)
      return n if n
    end
    nil
  end

  def keep(k)
    @nodes = @nodes.map { |n| n.keep(k) }.compact
    @nodes.each {|n| n.parent = self }
    @nodes.length <= 1 ? @nodes.first : self
  end

  def append(window)
    @nodes << Leaf.new(window, parent: self)
  end
    
  def place_adjacent(window, focus, dir)
    if nodes.length == 2
      i = nodes.index(focus) || 1
      dir ||= Node.swapdir(@dir) || :lr
      @nodes[i] = Node.new([focus, Leaf.new(window)], parent: self, dir: dir)
    else
      append(window)
    end
  end

  def split(i)
    @nodes[i] = Node.new(@nodes[i], parent: self) if @nodes[i].is_a?(Leaf)
    @nodes[i]
  end
      
  def place(window)
    case @nodes.length
    when 0..1 then append(window)
    when 2    then split(1).place(window)
    else raise
    end
  end

  def self.swapdir(dir) = {lr: :tb, tb: :lr}[dir]

  def layout(geom, gap=GAP, dir = :lr, level = 0)
    @dir ||= dir
    dir = @dir
    nextdir = Node.swapdir(dir)
    @geom = geom.dup
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
      @nodes[0].layout(split_geom(geom, dir, 0,gap, @ratio), gap, nextdir, level+1)
      @nodes[1].layout(split_geom(geom, dir, 1,gap, @ratio), gap, nextdir, level+1)
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
