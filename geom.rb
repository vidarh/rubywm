
module X11
  module Form
    class Geometry
      def inspect = "<Geometry x=#{x.to_i} y=#{y.to_i} width=#{width.to_i} height=#{height.to_i}>"
    end
  end
  end
  
def gap(geom,g)
  geom = geom.dup
  geom.x += g
  geom.width -= g*2
  geom.y += g
  geom.height -= g*2
  geom
end

def split_geom(geom, dir, node, gap, ratio)
  geom = geom.dup
  case dir
  when :lr
    lw = (geom.width-gap)*ratio
    if node == 0
      geom.width = lw
    else
      geom.width = (geom.width-gap)*(1.0-ratio)
      geom.x += lw + gap
    end
    return geom
  when :tb
    th = (geom.height-gap)*ratio
    if node == 0
      geom.height = th
    else
      geom.height = (geom.height-gap)*(1.0-ratio)
      geom.y += th + gap
    end
    return geom
  else raise "Invalid direction"
  end
end

# FIXME: This needs tweaks. Especially for floating windows, where
# what we really want is to e.g. treat partially overlapping windows
# so that the one closest to *overlapping* the correct border is picked
def find_closest(w, dir, from)
  return nil if from.empty?
  
  g = w.get_geometry rescue nil # FIXME
  return nil if g.nil?
  
  predicate = case dir
      when :left  then predicate = ->(g2) { g.x  - (g2.x + g2.width)  }
      when :right then predicate = ->(g2) { g2.x - (g.x  + g.width)   }
      when :up    then predicate = ->(g2) { g.y  - (g2.y + g2.height) }
      when :down  then predicate = ->(g2) { g2.y - (g.y  + g.height)  }
      end
      
  secondary = case dir
      when :left, :right then ->(g2) { (g.y - g2.y).abs }
      else ->(g2) { (g.x - g2.x).abs }
      end

  return from.map do |win|
    g2 = win.get_geometry rescue nil
    next if g2.nil?
    [predicate.call(g2), secondary.call(g2), win]
  end.reject{|d1,d2, win| d1 < 0}
           .min_by{|d1,d2, win| [d1,d2] }&.last
end

