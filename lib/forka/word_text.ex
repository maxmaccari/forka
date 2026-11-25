defmodule Forka.WordText do
  @moduledoc """
  Pure text rules for dictionary words, shared by the `Forka.Words` and `Forka.Games`
  Contexts: normalization for distinctness (case and accents folded), supported input
  letters, and playability.
  """

  @supported_letters Enum.map(?A..?Z, &<<&1>>)
  @supported_normalized_letters MapSet.new(@supported_letters, &String.downcase/1)

  @doc """
  Returns the canonical list of uppercase letters supported by the game input.
  """
  @spec supported_letters() :: [String.t()]
  def supported_letters, do: @supported_letters

  @doc """
  Normalizes dictionary word text for distinctness comparison by folding accents and
  diacritics, stripping non-letter/space/hyphen characters, collapsing repeated spaces
  and hyphens, trimming, and downcasing.
  """
  @spec normalize_text(String.t() | nil) :: String.t()
  def normalize_text(nil), do: ""

  def normalize_text(text) when is_binary(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\p{L}\s\-]+/u, "")
    |> String.replace(~r/\s{2,}/u, " ")
    |> String.replace(~r/-{2,}/u, "-")
    |> String.trim()
    |> String.downcase()
    |> String.normalize(:nfc)
  end

  @doc """
  Returns true when `text` contains at least one letter after normalization and every
  normalized letter is supported by `supported_letters/0`.
  """
  @spec playable_text?(term()) :: boolean()
  def playable_text?(text) when is_binary(text) do
    letters =
      text
      |> normalize_text()
      |> String.replace(~r/[\s\-]+/u, "")
      |> String.graphemes()

    letters != [] and Enum.all?(letters, &MapSet.member?(@supported_normalized_letters, &1))
  end

  def playable_text?(_other), do: false
end
