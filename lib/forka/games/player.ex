defmodule Forka.Games.Player do
  defstruct id: nil, username: nil, score: 0

  # TODO: Temporary, as it will come from Ecto
  def new(username) when is_binary(username) do
    %__MODULE__{
      id: UUID.uuid4(),
      username: username
    }
  end
end
