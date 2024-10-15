local show = pd.Class:new():register("show~")

function show:initialize(sel, atoms)
  self.inlets = {SIGNAL}
  self:reset()
  self.colors = {
    {0, 0, 0},
    {31, 119, 180},   -- Steel Blue
    {214, 39, 40},    -- Brick Red
    {44, 160, 44},    -- Cooked Asparagus Green
    {148, 103, 189},  -- Muted Purple
    {255, 127, 14},   -- Safety Orange
    {140, 86, 75},    -- Chestnut Brown
    {227, 119, 194},  -- Medium Pink
    {127, 127, 127},  -- Medium Gray
    {188, 189, 34},   -- Olive Green
    {23, 190, 207},   -- Cyan
    {158, 218, 229},  -- Light Blue
    {199, 199, 199},  -- Light Gray
    {219, 219, 141},  -- Pale Yellow
    {255, 187, 120},  -- Light Orange
    {152, 223, 138},  -- Light Green
    {255, 152, 150}   -- Light Red
  }
  return true
end

function show:postinitialize()
  self.clock = pd.Clock:new():register(self, "tick")
  self.clock:delay(0)
end

function show:tick()
  self:repaint()
  -- pd.post("draw")
  self.clock:delay(self.frameDelay)
end

function show:reset()
  self.sampleIndex = 1
  self.bufferIndex = 1
  self.sigs = { {} }
  self.avgs = {}
  self.rms = {}
  self.interval = 1
  self.frameDelay = 20
  self.strokeWidth = 1
  self.graphWidth = 152
  self.valWidth = 48
  self.sigHeight = 16
  self.hover = 0
  self.max = 1
  self.maxVal = 0
  self.width = self.graphWidth + self.valWidth
  self.height = 140
  self:set_size(self.graphWidth + self.valWidth, self.height)
  -- self.colors = {{}}
end

function show:in_1_reset()
  self.reset()
end

function show:in_1_size(x)
  self.width, self.height = x[1], x[2]
  self:set_size(x[1], x[2])
end

function show:in_1_interval(x)
  self.interval = math.max(1, math.floor(x[1]) or 1)
end

function show:in_1_reset()
  self.reset()
end

function show:dsp(samplerate, blocksize, inchans)
  -- pd.post(string.format("samplerate %d, blocksize %d, inchans %d", samplerate, blocksize, table.unpack(inchans)))
  self.blocksize = blocksize
  self.inchans = inchans[1]
  self.sigs = {}
  self.height = self.inchans * self.sigHeight
  self.height = math.max(140, self.height)
  self:set_size(self.graphWidth + self.valWidth, self.height)
  for c = 1, self.inchans do
    self.rms[c] = 0
    self.avgs[c] = 0
    self.sigs[c] = self.sigs[c] or {}
  end
end

function show:getrange(maxValue)
    local baseValues = {1, 2, 5, 10}
    
    -- Find the appropriate power of 10
    local power = math.max(-1, math.floor(math.log(maxValue, 10)))
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
  -- FIXME: only iterate through samples once!!
  -- pd.post(table.unpack(in1))
  for c=1,self.inchans do
    for s=1,self.blocksize do
      local sample = in1[s + self.blocksize * (c-1)] or 0
      self.maxVal = math.max(math.abs(sample), self.maxVal)
      self.avgs[c] = self.avgs[c] * 0.9996 + sample * 0.0004 -- lowpassed avg
      self.rms[c] = self.rms[c] * 0.9996 + math.sqrt(sample * sample) * 0.0004 -- lowpassed rms
    end
  end
  self.maxVal = self.maxVal * 0.99
  self.max = self.max * 0.95 + self:getrange(self.maxVal) * 0.05

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
end

function show:mouse_move(x, y)
   -- 0 for no hover, otherwise signal index
  if x >= self.graphWidth and x <= self.width then
    self.hover = math.min(y // self.sigHeight + 1, self.inchans or 0)
  else 
    self.hover = 0
  end
end

function show:paint(g)
  g:set_color(248, 248, 248)
  g:fill_all()
  g:set_color(200, 200, 200)
  g:draw_line(0, self.height/2, self.graphWidth, self.height/2, 1)
  for idx=1, #self.sigs do
    local i = (self.hover + idx - 1) % #self.sigs + 1
    local sig = self.sigs[i] 
    local markthis = i == self.hover -- true if index should be marked
    local color = self.hover == 0 and self.colors[i] or (markthis and {0, 0, 0} or {192, 192, 192})
    if markthis then
      g:set_color(table.unpack(color))
      g:draw_text(string.format("ch %d", i), 3, 3, 64, 10);
    end
    g:set_color(table.unpack(markthis and {180, 180, 180} or {216, 216, 216}))
    g:fill_rect(self.graphWidth, self.sigHeight * (i-1) + 1, self.valWidth*math.min(1, self.rms[i] or 0), self.sigHeight-1)
    g:set_color(table.unpack(color or {216, 216, 216}))
    local y = (sig[(self.bufferIndex-1) % self.graphWidth + 1] or 0) / self.max * -self.height/2 + self.height/2
    local p = Path(0, y)
    for x = 1, self.graphWidth-1 do
      y = (sig[(self.bufferIndex-1 + x) % self.graphWidth + 1] or 0) / self.max * -self.height/2 + self.height/2
      p:line_to(x, y)
    end
    g:stroke_path(p, self.strokeWidth)
    color = self.hover == 0 and self.colors[i] or (markthis and {0, 0, 0} or {144, 144, 144})
    g:set_color(table.unpack(color))
    g:draw_text(string.format("% 7.2f", self.avgs[i] or 0), self.graphWidth + 4, i * self.sigHeight - 13, self.graphWidth, 10);
  end
  g:set_color(0, 0, 0)
  -- g:stroke_rect(0, 0, self.graphWidth, self.height, 1)
  g:draw_text(string.format("% 8.1f", self.max), self.graphWidth-50, 3, 50, 10);
  -- g:draw_text(" 0.0", self.graphWidth-26, self.height/2-5, 24, 10);
  g:draw_text(string.format("% 8.1f", -self.max), self.graphWidth-50, self.height-12, 50, 10);
  g:draw_text(string.format("1px = %dsp", self.interval), 2, self.height-12, 70, 10);
end
