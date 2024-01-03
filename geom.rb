
def gap(geom,g)
  geom = geom.dup
  geom.x += g
  geom.width -= g*2
  geom.y += g
  geom.height -= g*2
  geom
end

def split_geom(geom, dir, node, gap)
  geom = geom.dup
  case dir
  when :lr
    geom.width = (geom.width-gap)/2
    geom.x += geom.width+gap if node == 1
    return geom
  when :tb
    geom.height = (geom.height-gap)/2
    geom.y += geom.height+gap if node == 1
    return geom
  else raise "Invalid direction"
  end
end
