// Swift replacement for absl::Status / absl::StatusOr used by the GenmaiBase
// ports (file_util, mmap, temp_dir, ...). Functions that return absl::Status
// in C++ `throw` a `StatusError` in Swift; absl::StatusOr<T> becomes a
// throwing function returning T.

#if canImport(Darwin)
  import Darwin
#endif

/// absl::StatusCode.
public enum StatusCode: Int, Sendable, CustomStringConvertible {
  case ok = 0
  case cancelled = 1
  case unknown = 2
  case invalidArgument = 3
  case deadlineExceeded = 4
  case notFound = 5
  case alreadyExists = 6
  case permissionDenied = 7
  case resourceExhausted = 8
  case failedPrecondition = 9
  case aborted = 10
  case outOfRange = 11
  case unimplemented = 12
  case `internal` = 13
  case unavailable = 14
  case dataLoss = 15
  case unauthenticated = 16

  public var description: String {
    switch self {
    case .ok: "OK"
    case .cancelled: "CANCELLED"
    case .unknown: "UNKNOWN"
    case .invalidArgument: "INVALID_ARGUMENT"
    case .deadlineExceeded: "DEADLINE_EXCEEDED"
    case .notFound: "NOT_FOUND"
    case .alreadyExists: "ALREADY_EXISTS"
    case .permissionDenied: "PERMISSION_DENIED"
    case .resourceExhausted: "RESOURCE_EXHAUSTED"
    case .failedPrecondition: "FAILED_PRECONDITION"
    case .aborted: "ABORTED"
    case .outOfRange: "OUT_OF_RANGE"
    case .unimplemented: "UNIMPLEMENTED"
    case .internal: "INTERNAL"
    case .unavailable: "UNAVAILABLE"
    case .dataLoss: "DATA_LOSS"
    case .unauthenticated: "UNAUTHENTICATED"
    }
  }
}

/// A non-OK absl::Status.
public struct StatusError: Error, Sendable, Equatable, CustomStringConvertible {
  public var code: StatusCode
  public var message: String

  public init(_ code: StatusCode, _ message: String = "") {
    self.code = code
    self.message = message
  }

  public var description: String { "\(code): \(message)" }

  public static func unknown(_ m: String) -> StatusError { .init(.unknown, m) }
  public static func invalidArgument(_ m: String) -> StatusError { .init(.invalidArgument, m) }
  public static func notFound(_ m: String) -> StatusError { .init(.notFound, m) }
  public static func alreadyExists(_ m: String) -> StatusError { .init(.alreadyExists, m) }
  public static func failedPrecondition(_ m: String) -> StatusError { .init(.failedPrecondition, m) }
  public static func permissionDenied(_ m: String) -> StatusError { .init(.permissionDenied, m) }
  public static func outOfRange(_ m: String) -> StatusError { .init(.outOfRange, m) }
  public static func unimplemented(_ m: String) -> StatusError { .init(.unimplemented, m) }
  public static func dataLoss(_ m: String) -> StatusError { .init(.dataLoss, m) }
  public static func `internal`(_ m: String) -> StatusError { .init(.internal, m) }

  /// absl::ErrnoToStatus.
  public static func errno(_ err: Int32, _ message: String) -> StatusError {
    let str = String(cString: strerror(err))
    return StatusError(errnoToStatusCode(err), "\(message): \(str)")
  }
}

/// absl::ErrnoToStatusCode.
public func errnoToStatusCode(_ err: Int32) -> StatusCode {
  switch err {
  case 0:
    return .ok
  case EINVAL, ENAMETOOLONG, E2BIG, EDESTADDRREQ, EDOM, EFAULT, EILSEQ, ENOPROTOOPT,
    ENOTSOCK, ENOTTY, EPROTOTYPE, ESPIPE:
    return .invalidArgument
  case ETIMEDOUT, ETIME:
    return .deadlineExceeded
  case ENODEV, ENOENT, ENXIO, ESRCH:
    return .notFound
  case EEXIST, EADDRNOTAVAIL, EALREADY:
    return .alreadyExists
  case EPERM, EACCES, EROFS:
    return .permissionDenied
  case ENOTEMPTY, EISDIR, ENOTDIR, EADDRINUSE, EBADF, EBUSY, ECHILD, EISCONN, ENOTBLK,
    ENOTCONN, EPIPE, ESHUTDOWN, ETXTBSY:
    return .failedPrecondition
  case ENOSPC, EDQUOT, EMFILE, EMLINK, ENFILE, ENOBUFS, ENODATA, ENOMEM, ENOSR, EUSERS:
    return .resourceExhausted
  case EFBIG, EOVERFLOW, ERANGE:
    return .outOfRange
  case ENOEXEC, ENOSYS, ENOTSUP, EAFNOSUPPORT, EPFNOSUPPORT, EPROTONOSUPPORT,
    ESOCKTNOSUPPORT, EXDEV:
    return .unimplemented
  case EAGAIN, ECONNREFUSED, ECONNABORTED, ECONNRESET, EINTR, EHOSTDOWN, EHOSTUNREACH,
    ENETDOWN, ENETRESET, ENETUNREACH, ENOLCK, ENOLINK:
    return .unavailable
  case EDEADLK, ESTALE:
    return .aborted
  case ECANCELED:
    return .cancelled
  default:
    return .unknown
  }
}

extension Error {
  /// The absl::StatusCode of this error (`.unknown` for non-StatusError).
  public var statusCode: StatusCode {
    (self as? StatusError)?.code ?? .unknown
  }
}
