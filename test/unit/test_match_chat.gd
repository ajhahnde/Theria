extends GutTest
## Behavioural checks on the chat box — the bottom-left all/team chat. They verify the typing
## gate (open / close drives `is_typing`, which the driver reads to suppress casts), the scope
## toggle, and that a sent line is echoed locally and announced while a blank send is dropped.
## Network delivery is a later slice and is not exercised here — the local echo and the gate are
## the whole of the first-pass logic.


func _chat() -> MatchChat:
	var chat := MatchChat.new()
	add_child_autoqfree(chat)
	return chat


func test_starts_not_typing() -> void:
	assert_false(_chat().is_typing(), "chat starts closed, so the game keeps the keyboard")


func test_open_enters_typing() -> void:
	var chat := _chat()
	chat.open()
	assert_true(chat.is_typing(), "opening chat captures typing so a key does not also cast")


func test_close_releases_typing() -> void:
	var chat := _chat()
	chat.open()
	chat.close()
	assert_false(chat.is_typing(), "closing hands the keyboard back to the game")


func test_toggle_scope_flips_all_and_team() -> void:
	var chat := _chat()
	assert_eq(chat._scope, MatchChat.Scope.ALL, "chat defaults to all-chat")
	chat.toggle_scope()
	assert_eq(chat._scope, MatchChat.Scope.TEAM, "toggling switches to team-chat")
	chat.toggle_scope()
	assert_eq(chat._scope, MatchChat.Scope.ALL, "toggling again switches back")


func test_sending_echoes_locally_and_announces() -> void:
	var chat := _chat()
	chat.open()
	watch_signals(chat)
	chat._on_submitted("hello")
	assert_eq(chat._log.get_child_count(), 1, "a sent line is echoed into the local log")
	assert_signal_emitted_with_parameters(chat, "message_sent", [MatchChat.Scope.ALL, "hello"])
	assert_false(chat.is_typing(), "sending closes the input")


func test_blank_send_is_dropped() -> void:
	var chat := _chat()
	chat.open()
	chat._on_submitted("   ")
	assert_eq(chat._log.get_child_count(), 0, "a blank line is not logged")
	assert_false(chat.is_typing(), "a blank send still closes the input")


func test_log_caps_its_length() -> void:
	var chat := _chat()
	for i in MatchChat.MAX_LINES + 4:
		chat.append_line("You", "line %d" % i, MatchChat.Scope.ALL)
	assert_eq(chat._log.get_child_count(), MatchChat.MAX_LINES, "the log drops the oldest line")
