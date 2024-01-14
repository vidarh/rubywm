
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
