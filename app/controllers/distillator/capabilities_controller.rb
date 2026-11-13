module Distillator
  class CapabilitiesController < ApplicationController
    def index
      @capability_map = Distillator::CapabilityMap.call
    end
  end
end
