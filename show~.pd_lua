local show = pd.Class:new():register("show~")

function show:initialize(sel, args)
  self.inlets = {SIGNAL}
  self.outlets = {DATA}
  self.graphWidth = 152
  self.interval = 1
  self.colors = {}
  self.needsRepaintBackground = true
  self.needsRepaintLegend = true
  self.scale = nil
  for i, arg in ipairs(args) do
    if arg == "-scale" then
      self.scale = type(args[i+1]) == "number" and args[i+1] or 1
    elseif arg == "-width" then
      self.graphWidth = math.max(math.floor(args[i+1] or 152), 96)
    elseif arg == "-interval" then
      self.interval = math.abs(args[i+1] or 1)
    end
  end
  self:reset()
  return true
end

function show:postinitialize()
  self.clock = pd.Clock:new():register(self, "tick")
  self.clock:delay(0)
end

function show:tick()
  if self.needsRepaintBackground then
    self:repaint(1)
    self.needsRepaintBackground = false
  end
  self:repaint(2)  -- Always repaint the graphs (layer 2)
  if self.needsRepaintLegend then
    self:repaint(3)
    self.needsRepaintLegend = false
  end
  self.clock:delay(self.frameDelay)
end

function show:reset()
  self.sampleIndex = 1
  self.bufferIndex = 1
  self.sigs = {}
  self.avgs = {}
  self.rms = {}
  self.inchans = 0
  self.frameDelay = 20
  self.strokeWidth = 1
  self.valWidth = 48
  self.sigHeight = 16
  self.hover = 0
  self.max = 1
  self.maxVal = 1
  self.width = self.graphWidth + self.valWidth
  self.height = 140
  self.dragStart = nil
  self.dragStartInterval = nil
  self.hoverGraph = false
  self.hoverInterval = false
  self.needsRepaintBackground = true
  self.needsRepaintLegend = true
  self:update_layout()
end

function show:in_1_reset()
  self.reset()
end

function show:get_channel_from_point(x, y)
  if self:point_in_rect(x, y, self.channelRect) then
    return math.floor(y / self.sigHeight) + 1
  end
  return 0
end

function show:update_layout()
  self.intervalRect = {x = 1, y = self.height - 15, width = self.graphWidth - 1, height = 15}
  self.graphRect = {x = 0, y = self.height/2, width = self.graphWidth, height = self.height/2 - 15}
  self.channelRect = {x = self.graphWidth, y = 0, width = self.valWidth, height = self.height}
  self:set_size(self.graphWidth + self.valWidth, self.height)
end

function show:in_1_width(x)
  self.graphWidth = math.max(math.floor(x[1] or 152), 96)
  self:set_args({self.graphWidth})
  self:update_layout()
  for i=1, self.inchans do
    self.sigs[i] = {}
  end
  self.needsRepaintBackground = true
  self.needsRepaintLegend = true
end

function show:mouse_move(x, y)
  local oldHover = self.hover
  if self:point_in_rect(x, y, self.channelRect) then
    self.hover = math.max(0, math.floor((y - self.channelRect.y) / self.sigHeight) + 1)
    if self.hover > self.inchans then self.hover = 0 end
  else
    self.hover = 0
  end

  local oldHoverInterval = self.hoverInterval
  local oldHoverGraph = self.hoverGraph
  
  self.hoverGraph = self:point_in_rect(x, y, self.graphRect)
  self.hoverInterval = self:point_in_rect(x, y, self.intervalRect)

  if oldHover ~= self.hover or oldHoverInterval ~= self.hoverInterval or oldHoverGraph ~= self.hoverGraph then
    self.needsRepaintLegend = true
  end
end

function show:mouse_drag(x, y)
  if self.dragStart then
    local dx = x - self.dragStart
    local scaleFactor = 0.05
    local newInterval = math.max(1, math.floor(self.dragStartInterval * math.exp(dx * scaleFactor)))
    if newInterval ~= self.interval then
      self:in_1_interval({newInterval})
    end
  end
end

function show:mouse_down(x, y)
  if self.hoverInterval then
    self.dragStart = x
    self.dragStartInterval = self.interval
  end
end

function show:mouse_up(x, y)
  self.dragStart = nil
  self.dragStartInterval = nil
end

function show:point_in_rect(x, y, rect)
  return x >= rect.x and x <= rect.x + rect.width and
         y >= rect.y and y <= rect.y + rect.height
end

function show:in_1_interval(x)
  self.interval = math.max(1, math.floor(x[1] or 1))
  self.needsRepaintLegend = true
end

function show:in_1_scale(x)
  self.scale = x[1]
end

function show:in_1_reset()
  self.reset()
end

function show:in_1_bang()
  local output = {}
  for i = 1, self.inchans do
    output[i] = self.sigs[i][(self.bufferIndex - 2) % self.graphWidth + 1]
  end
  self:outlet(1, "list", output)
end

function show:getrange(maxValue)
  local baseValues = {1, 2, 5, 10}
  
  -- Find the appropriate power of 10
  local power = math.max(0, math.floor(math.log(maxValue, 10)))
  local scale = 10^power
  
  -- Normalize the maxValue to between 0 and 10
  local normalizedValue = maxValue / scale
  
  -- Find the first base value that's greater than or equal to the normalized value
  for _, base in ipairs(baseValues) do
    if base >= normalizedValue then
      return base * scale
    end
  end
  
  -- If we get here, normalizedValue must be 10, so we return the next scale up
  return baseValues[1] * (scale * 10)
end

function show:perform(in1)
  for c=1,self.inchans do
    for s=1,self.blocksize do
      local sample = in1[s + self.blocksize * (c-1)] or 0
      self.maxVal = math.max(math.abs(sample), self.maxVal)
      self.avgs[c] = self.avgs[c] * 0.9996 + sample * 0.0004 -- lowpassed avg
      self.rms[c] = self.rms[c] * 0.9996 + math.sqrt(sample * sample) * 0.0004 -- lowpassed rms
    end
  end
  
  while self.sampleIndex <= self.blocksize do
    -- ring buffer
    for i=1,self.inchans do
      self.sigs[i][self.bufferIndex] = in1[self.sampleIndex + self.blocksize * (i-1)]
    end
    -- bufferIndex is the index with the "oldest" sample in the ring buffer
    self.bufferIndex = self.bufferIndex % self.graphWidth + 1
    self.sampleIndex = self.sampleIndex + self.interval
  end
  -- sampleIndex is the index where we start reading from the next sample block
  self.sampleIndex = self.sampleIndex - self.blocksize
  
  -- Gradual decay of maxVal
  self.maxVal = self.maxVal * 0.99

  -- Calculate target max value
  local targetMax = self.scale or self:getrange(self.maxVal)
  
  -- Smooth transition of max value
  local transitionSpeed = 0.02  -- Adjust this value to control transition speed
  self.max = self.max + (targetMax - self.max) * transitionSpeed

  if self.max ~= targetMax then
    self.needsRepaintLegend = true
  end
end

function show:paint(g)
  -- Background
  g:set_color(248, 248, 248)
  g:fill_all()
end

function show:paint_layer_2(g)
  g:set_color(200, 200, 200)
  g:draw_line(0, self.height/2, self.graphWidth - 1, self.height/2, 1)
  -- Graphs, RMS charts, and avg values

  if self.hover == 0 then
    -- No channel highlighted: draw in reverse order
    for idx = #self.sigs, 1, -1 do
      self:draw_channel(g, idx, false)
    end
  else
    -- Channel highlighted: draw non-highlighted channels first, then the highlighted one
    for idx = 1, #self.sigs do
      if idx ~= self.hover then
        self:draw_channel(g, idx, false)
      end
    end
    if self.hover <= #self.sigs then
      self:draw_channel(g, self.hover, true)
    end
  end
end

function show:paint_layer_3(g)
  -- Draw interval hover
  if self.hoverGraph or self.hoverInterval or self.dragStart then
    if self.hoverInterval or self.dragStart then
      g:set_color(200, 200, 200)  -- Darker gray for direct hover or dragging
    else
      g:set_color(230, 230, 230)  -- Light gray for graph area hover
    end
    g:fill_rect(self.intervalRect.x, self.intervalRect.y, self.intervalRect.width, self.intervalRect.height)
  end
  
  -- Legend: range text, channel if hovered, and scale
  local intervalText = string.format("1px = %dsp", self.interval)
  g:set_color(0, 0, 0)
  g:draw_text(intervalText, 3, self.height-13, 100, 10)
  g:draw_text(string.format("% 8.2f", self.max), self.graphWidth-50, 3, 50, 10)
  g:draw_text(string.format("% 8.2f", -self.max), self.graphWidth-50, self.height-13, 50, 10)

  -- Draw hovered channel number
  if self.hover > 0 and self.hover <= #self.sigs then
    g:set_color(table.unpack(self.colors[self.hover] or {0, 0, 0}))
    g:draw_text(string.format("ch %d", self.hover), 3, 3, 64, 10)
  end
end

function show:draw_channel(g, idx, isHovered)
  local sig = self.sigs[idx]
  if not sig then return end  -- Skip drawing if the signal doesn't exist

  local color = self.colors[idx] or {255, 255, 255}  -- Default to white if color is not set
  local graphColor = (self.hover == 0 or isHovered) and color or {192, 192, 192}
  
  -- RMS bar
  g:set_color(table.unpack(isHovered and {180, 180, 180} or {216, 216, 216}))
  g:fill_rect(self.graphWidth, self.sigHeight * (idx-1) + 1, self.valWidth*math.min(1, self.rms[idx] or 0), self.sigHeight-1)
  
  -- Graph line
  g:set_color(table.unpack(graphColor))
  
  local function scaleY(value)
    -- Scale the value to fit within the height, leaving 1px margin at top and bottom
    return (value / self.max * -0.5 + 0.5) * (self.height - 2) + 1
    -- return scaledY -- math.max(1, math.min(self.height - 1, scaledY)) -- FIXME: clip?
  end

  local x0 = (self.bufferIndex - 1) % self.graphWidth
  local y0 = scaleY(sig[x0 + 1] or 0)
  local p = Path(0, y0)
  
  for x = 1, self.graphWidth - 2 do  -- Changed to self.graphWidth - 2
    local bufferX = (x0 + x) % self.graphWidth + 1
    local y = scaleY(sig[bufferX] or 0)
    p:line_to(x, y)
  end
  
  g:stroke_path(p, self.strokeWidth)
  
  -- Average value text
  g:set_color(table.unpack((self.hover == 0 or isHovered) and color or {144, 144, 144}))
  g:draw_text(string.format("% 7.2f", self.avgs[idx] or 0), self.graphWidth + 4, idx * self.sigHeight - 13, self.valWidth, 10)
end

function show:dsp(samplerate, blocksize, inchans)
  -- pd.post(string.format("samplerate %d, blocksize %d, inchans %d", samplerate, blocksize, table.unpack(inchans)))
  self.blocksize = blocksize
  self.inchans = inchans[1]
  self.sigs = {}
  self.height = self.inchans * self.sigHeight
  self.height = math.max(140, self.height)

  self.needsRepaintBackground = true
  self.needsRepaintLegend = true
  self:update_layout()  -- Update overlay and hover areas

  self.colors = self:generate_colors(self.inchans)
 
  for c = 1, self.inchans do
    self.rms[c] = 0
    self.avgs[c] = 0
    self.sigs[c] = {}  -- Initialize an empty table for each channel
  end
  
  -- Reset hover state when channel count changes
  self.hover = 0
end

function show:hsv_to_rgb(h, s, v)
  h = h % 360  -- Ensure h is in the range 0-359
  s = s / 100  -- Convert s to 0-1 range
  v = v / 100  -- Convert v to 0-1 range

  local c = v * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = v - c

  local r, g, b
  if h < 60 then
    r, g, b = c, x, 0
  elseif h < 120 then
    r, g, b = x, c, 0
  elseif h < 180 then
    r, g, b = 0, c, x
  elseif h < 240 then
    r, g, b = 0, x, c
  elseif h < 300 then
    r, g, b = x, 0, c
  else
    r, g, b = c, 0, x
  end

  -- Scale to 0-255 range and round to nearest integer
  return math.floor((r + m) * 255 + 0.5), 
         math.floor((g + m) * 255 + 0.5), 
         math.floor((b + m) * 255 + 0.5)
end

function show:generate_colors(count)
  local colors = {}
  local hue_start, hue_end = 210, 340
  local saturation = 90
  local brightness_start, brightness_end = 70, 80

  for i = 1, count do
    local hue = hue_start + (hue_end - hue_start) * ((i - 1) / math.max(1, count - 1))
    local brightness = brightness_start + (brightness_end - brightness_start) * ((i - 1) / math.max(1, count - 1))
    local r, g, b = self:hsv_to_rgb(hue, saturation, brightness)
    table.insert(colors, {r, g, b})
  end

  return colors
end
