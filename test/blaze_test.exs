defmodule BlazeTest do
  use ExUnit.Case
  doctest Blaze

  test "greets the world" do
    assert Blaze.hello() == :world
  end
end
