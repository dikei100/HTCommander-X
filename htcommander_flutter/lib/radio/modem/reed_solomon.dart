/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Reed-Solomon GF(2^8) codec: encoding and Berlekamp-Massey decoding.
/// Port of HTCommander.Core/hamlib/ReedSolomonCodec.cs and the RS parts of
/// Fx25.cs (InitRs, codec control block).
library;

import 'dart:typed_data';

/// Reed-Solomon codec control block.
class ReedSolomonCodec {
  final int mm; // Bits per symbol
  final int nn; // Symbols per block = (1<<mm)-1
  final Uint8List alphaTo; // log lookup table
  final Uint8List indexOf; // Antilog lookup table
  final Uint8List genPoly; // Generator polynomial (index form)
  final int nRoots; // Number of parity symbols
  final int fcr; // First consecutive root
  final int prim; // Primitive element
  final int iPrim; // prim-th root of 1

  ReedSolomonCodec._({
    required this.mm,
    required this.nn,
    required this.alphaTo,
    required this.indexOf,
    required this.genPoly,
    required this.nRoots,
    required this.fcr,
    required this.prim,
    required this.iPrim,
  });

  /// Modulo NN operation optimised for Reed-Solomon.
  int modNN(int x) {
    while (x >= nn) {
      x -= nn;
      x = (x >> mm) + (x & nn);
    }
    return x;
  }

  /// Initialize a Reed-Solomon codec.
  ///
  /// Returns `null` if parameters are invalid.
  static ReedSolomonCodec? create({
    required int symsize,
    required int gfpoly,
    required int fcr,
    required int prim,
    required int nroots,
  }) {
    if (symsize > 8) return null;
    final int limit = 1 << symsize;
    if (fcr >= limit) return null;
    if (prim == 0 || prim >= limit) return null;
    if (nroots >= limit) return null;

    final int nn = limit - 1;
    final alphaTo = Uint8List(nn + 1);
    final indexOf = Uint8List(nn + 1);

    // Generate Galois field lookup tables.
    indexOf[0] = nn; // log(zero) = -inf
    alphaTo[nn] = 0; // alpha**-inf = 0

    int sr = 1;
    for (int i = 0; i < nn; i++) {
      indexOf[sr] = i;
      alphaTo[i] = sr;
      sr <<= 1;
      if ((sr & limit) != 0) sr ^= gfpoly;
      sr &= nn;
    }

    if (sr != 1) return null; // Not primitive

    // Build generator polynomial.
    final genPoly = Uint8List(nroots + 1);
    genPoly[0] = 1;

    int root = fcr * prim;
    for (int i = 0; i < nroots; i++, root += prim) {
      genPoly[i + 1] = 1;
      for (int j = i; j > 0; j--) {
        if (genPoly[j] != 0) {
          genPoly[j] = genPoly[j - 1] ^
              alphaTo[_modNN(indexOf[genPoly[j]] + root, nn, symsize)];
        } else {
          genPoly[j] = genPoly[j - 1];
        }
      }
      genPoly[0] = alphaTo[_modNN(indexOf[genPoly[0]] + root, nn, symsize)];
    }

    // Convert to index form.
    for (int i = 0; i <= nroots; i++) {
      genPoly[i] = indexOf[genPoly[i]];
    }

    // Find prim-th root of 1.
    int iprim = 1;
    while ((iprim % prim) != 0) {
      iprim += nn;
    }
    iprim ~/= prim;

    return ReedSolomonCodec._(
      mm: symsize,
      nn: nn,
      alphaTo: alphaTo,
      indexOf: indexOf,
      genPoly: genPoly,
      nRoots: nroots,
      fcr: fcr,
      prim: prim,
      iPrim: iprim,
    );
  }

  static int _modNN(int x, int nn, int mm) {
    while (x >= nn) {
      x -= nn;
      x = (x >> mm) + (x & nn);
    }
    return x;
  }
}

/// Reed-Solomon encode / decode operations.
class ReedSolomon {
  ReedSolomon._();

  /// Encode data with Reed-Solomon error correction.
  ///
  /// [data] - Data to encode (length >= rs.nn - rs.nRoots).
  /// [bb]   - Output check bytes (length >= rs.nRoots).
  static void encode(ReedSolomonCodec rs, Uint8List data, Uint8List bb) {
    for (int i = 0; i < rs.nRoots; i++) {
      bb[i] = 0;
    }

    for (int i = 0; i < rs.nn - rs.nRoots; i++) {
      final int feedback = rs.indexOf[data[i] ^ bb[0]];
      if (feedback != rs.nn) {
        for (int j = 1; j < rs.nRoots; j++) {
          bb[j] ^=
              rs.alphaTo[rs.modNN(feedback + rs.genPoly[rs.nRoots - j])];
        }
      }

      // Shift.
      for (int j = 0; j < rs.nRoots - 1; j++) {
        bb[j] = bb[j + 1];
      }

      if (feedback != rs.nn) {
        bb[rs.nRoots - 1] =
            rs.alphaTo[rs.modNN(feedback + rs.genPoly[0])];
      } else {
        bb[rs.nRoots - 1] = 0;
      }
    }
  }

  /// Decode data with Reed-Solomon error correction.
  ///
  /// [data]    - Data block (length >= rs.nn), corrected in place.
  /// [erasPos] - Erasure positions (can be null).
  /// [noEras]  - Number of erasures.
  /// Returns number of errors corrected, or -1 if uncorrectable.
  static int decode(ReedSolomonCodec rs, Uint8List data,
      {List<int>? erasPos, int noEras = 0}) {
    final int nRoots = rs.nRoots;
    final int nn = rs.nn;

    final lambda = Uint8List(nRoots + 1);
    final s = Uint8List(nRoots);
    final b = Uint8List(nRoots + 1);
    final t = Uint8List(nRoots + 1);
    final omega = Uint8List(nRoots + 1);
    final root = Uint8List(nRoots);
    final reg = Uint8List(nRoots + 1);
    final loc = Uint8List(nRoots);

    // Form syndromes.
    for (int i = 0; i < nRoots; i++) {
      s[i] = data[0];
    }
    for (int j = 1; j < nn; j++) {
      for (int i = 0; i < nRoots; i++) {
        if (s[i] == 0) {
          s[i] = data[j];
        } else {
          s[i] = data[j] ^
              rs.alphaTo[
                  rs.modNN(rs.indexOf[s[i]] + (rs.fcr + i) * rs.prim)];
        }
      }
    }

    int synError = 0;
    for (int i = 0; i < nRoots; i++) {
      synError |= s[i];
      s[i] = rs.indexOf[s[i]];
    }

    if (synError == 0) return 0; // No errors.

    lambda[0] = 1;

    if (noEras > 0 && erasPos != null) {
      lambda[1] =
          rs.alphaTo[rs.modNN(rs.prim * (nn - 1 - erasPos[0]))];
      for (int i = 1; i < noEras; i++) {
        final int u =
            rs.alphaTo[rs.modNN(rs.prim * (nn - 1 - erasPos[i]))];
        for (int j = i + 1; j > 0; j--) {
          final int tmp = rs.indexOf[lambda[j - 1]];
          if (tmp != nn) {
            lambda[j] ^= rs.alphaTo[rs.modNN(u + tmp)];
          }
        }
      }
    }

    for (int i = 0; i < nRoots + 1; i++) {
      b[i] = rs.indexOf[lambda[i]];
    }

    // Berlekamp-Massey.
    int r = noEras;
    int el = noEras;
    while (++r <= nRoots) {
      int discrR = 0;
      for (int i = 0; i < r; i++) {
        if (lambda[i] != 0 && s[r - i - 1] != nn) {
          discrR ^=
              rs.alphaTo[rs.modNN(rs.indexOf[lambda[i]] + s[r - i - 1])];
        }
      }
      discrR = rs.indexOf[discrR];

      if (discrR == nn) {
        for (int i = nRoots; i > 0; i--) {
          b[i] = b[i - 1];
        }
        b[0] = nn;
      } else {
        t[0] = lambda[0];
        for (int i = 0; i < nRoots; i++) {
          if (b[i] != nn) {
            t[i + 1] = lambda[i + 1] ^
                rs.alphaTo[rs.modNN(discrR + b[i])];
          } else {
            t[i + 1] = lambda[i + 1];
          }
        }
        if (2 * el <= r + noEras - 1) {
          el = r + noEras - el;
          for (int i = 0; i <= nRoots; i++) {
            b[i] = (lambda[i] == 0)
                ? nn
                : rs.modNN(rs.indexOf[lambda[i]] - discrR + nn);
          }
        } else {
          for (int i = nRoots; i > 0; i--) {
            b[i] = b[i - 1];
          }
          b[0] = nn;
        }
        for (int i = 0; i < nRoots + 1; i++) {
          lambda[i] = t[i];
        }
      }
    }

    // Convert lambda to index form.
    int degLambda = 0;
    for (int i = 0; i < nRoots + 1; i++) {
      lambda[i] = rs.indexOf[lambda[i]];
      if (lambda[i] != nn) degLambda = i;
    }

    // Compute omega.
    int degOmega = 0;
    for (int i = 0; i < nRoots; i++) {
      int tmp = 0;
      final int jMax = degLambda < i ? degLambda : i;
      for (int j = jMax; j >= 0; j--) {
        if (s[i - j] != nn && lambda[j] != nn) {
          tmp ^= rs.alphaTo[rs.modNN(s[i - j] + lambda[j])];
        }
      }
      if (tmp != 0) degOmega = i;
      omega[i] = rs.indexOf[tmp];
    }
    omega[nRoots] = nn;

    // Chien search.
    for (int i = 1; i <= nRoots; i++) {
      reg[i] = lambda[i];
    }
    int count = 0;
    int k = rs.iPrim - 1;
    for (int i = 1; i <= nn; i++, k = rs.modNN(k + rs.iPrim)) {
      int q = 1;
      for (int j = degLambda; j > 0; j--) {
        if (reg[j] != nn) {
          reg[j] = rs.modNN(reg[j] + j);
          q ^= rs.alphaTo[reg[j]];
        }
      }
      if (q != 0) continue;

      root[count] = i;
      loc[count] = k;
      if (++count == degLambda) break;
    }

    if (degLambda != count) return -1; // Uncorrectable.

    // Compute error values.
    for (int j = count - 1; j >= 0; j--) {
      int num1 = 0;
      for (int i = degOmega; i >= 0; i--) {
        if (omega[i] != nn) {
          num1 ^= rs.alphaTo[rs.modNN(omega[i] + i * root[j])];
        }
      }
      final int num2 =
          rs.alphaTo[rs.modNN(root[j] * (rs.fcr - 1) + nn)];
      int den = 0;
      final int iMax =
          (degLambda < nRoots - 1 ? degLambda : nRoots - 1) & ~1;
      for (int i = iMax; i >= 0; i -= 2) {
        if (lambda[i + 1] != nn) {
          den ^= rs.alphaTo[rs.modNN(lambda[i + 1] + i * root[j])];
        }
      }
      if (den == 0) return -1;

      if (num1 != 0 && loc[j] < nn) {
        data[loc[j]] ^= rs.alphaTo[rs.modNN(
            rs.indexOf[num1] + rs.indexOf[num2] + nn - rs.indexOf[den])];
      }
    }

    return count;
  }
}
