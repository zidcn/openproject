class OpenProject::ToJsonNoOp
  def initialize(string)
    @string = string
  end

  def to_json(*_args)
    @string
  end
end
