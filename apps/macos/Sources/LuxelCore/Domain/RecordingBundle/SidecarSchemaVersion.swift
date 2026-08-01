func validatedSidecarSchemaVersion<ValidationError: Error>(
    _ schemaVersion: Int,
    current: Int,
    error: @autoclosure () -> ValidationError
) throws -> Int {
    guard schemaVersion == current else {
        throw error()
    }
    return schemaVersion
}
