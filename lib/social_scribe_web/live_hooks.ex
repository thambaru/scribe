defmodule SocialScribeWeb.LiveHooks do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:assign_current_path, _params, _session, socket) do
    socket =
      attach_hook(socket, :assign_current_path, :handle_params, &assign_current_path/3)

    {:cont, socket}
  end

  def on_mount(:attach_chat_sidebar, _params, _session, socket) do
    chat_open = Map.get(socket.assigns, :chat_open, false)
    {:cont, assign(socket, :chat_open, chat_open)}
  end

  defp assign_current_path(_params, uri, socket) do
    uri = URI.parse(uri)

    {:cont, assign(socket, :current_path, uri.path)}
  end
end
