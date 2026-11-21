defmodule Forka.IExHelpers do
  @moduledoc "Dev shortcuts available in IEx while the server is running."

  @doc "Opens the running application in the browser. Returns its URL."
  @spec o() :: String.t()
  def o, do: open_in_browser("/")

  @doc "Opens the Swoosh mailbox preview in the browser. Returns its URL."
  @spec m() :: String.t()
  def m, do: open_in_browser("/dev/mailbox")

  defp open_in_browser(path) do
    url = ForkaWeb.Endpoint.url() <> path
    {cmd, args} = opener(:os.type(), url)

    with executable when is_binary(executable) <- System.find_executable(cmd),
         {_output, 0} <- System.cmd(executable, args, stderr_to_stdout: true) do
      :ok
    else
      nil -> IO.puts("No `#{cmd}` found to open a browser. Visit #{url}")
      {output, status} -> IO.puts("`#{cmd}` exited with #{status}: #{output}Visit #{url}")
    end

    url
  end

  defp opener({:unix, :darwin}, url), do: {"open", [url]}
  defp opener({:unix, _}, url), do: {"xdg-open", [url]}
  defp opener({:win32, _}, url), do: {"cmd", ["/c", "start", "", url]}
end

import Forka.IExHelpers

IO.puts([
  IO.ANSI.faint(),
  "Shortcuts: ",
  IO.ANSI.reset(),
  IO.ANSI.cyan(),
  "o",
  IO.ANSI.reset(),
  " opens the app in the browser, ",
  IO.ANSI.cyan(),
  "m",
  IO.ANSI.reset(),
  " opens the mailbox"
])
