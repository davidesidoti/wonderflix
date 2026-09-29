import 'dart:io';

import 'package:dio/dio.dart';

/// Errori delle chiamate a Jellyfin, già classificati per la UI.
sealed class ApiException implements Exception {
  const ApiException();
}

final class UnauthorizedException extends ApiException {
  const UnauthorizedException();
}

final class ForbiddenException extends ApiException {
  const ForbiddenException();
}

final class NotFoundException extends ApiException {
  const NotFoundException();
}

final class ServerUnreachableException extends ApiException {
  const ServerUnreachableException([this.cause]);
  final Object? cause;

  @override
  String toString() => 'ServerUnreachableException($cause)';
}

final class ServerErrorException extends ApiException {
  const ServerErrorException(this.statusCode);
  final int? statusCode;

  @override
  String toString() => 'ServerErrorException($statusCode)';
}

/// Richiesta annullata dal client (es. una ricerca superata da una più recente).
final class RequestCancelledException extends ApiException {
  const RequestCancelledException();
}

ApiException mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.badResponse:
      return switch (e.response?.statusCode) {
        401 => const UnauthorizedException(),
        403 => const ForbiddenException(),
        404 => const NotFoundException(),
        final code => ServerErrorException(code),
      };
    case DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.transformTimeout ||
          DioExceptionType.connectionError ||
          DioExceptionType.badCertificate:
      return ServerUnreachableException(e.error ?? e.type);
    case DioExceptionType.cancel:
      return const RequestCancelledException();
    case DioExceptionType.unknown:
      final error = e.error;
      if (error is SocketException ||
          error is TlsException ||
          error is HttpException) {
        return ServerUnreachableException(error);
      }
      return const ServerErrorException(null);
  }
}
