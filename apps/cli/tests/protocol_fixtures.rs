use luxel_cli::protocol::{Command, Event, EventKind, Request};

#[test]
fn swift_request_fixture_decodes_in_rust() {
    let request: Request =
        serde_json::from_str(include_str!("../protocol/v1/fixtures/convert-request.json")).unwrap();
    assert_eq!(request.command, Command::Convert);
    assert!(request.arguments.convert.unwrap().mute);
}

#[test]
fn swift_result_fixture_decodes_in_rust() {
    let event: Event =
        serde_json::from_str(include_str!("../protocol/v1/fixtures/export-result.json")).unwrap();
    assert_eq!(event.kind, EventKind::Result);
    assert_eq!(
        event.result.unwrap().file_path.as_deref(),
        Some("/Users/example/Movies/Luxel/output.webm")
    );
}
