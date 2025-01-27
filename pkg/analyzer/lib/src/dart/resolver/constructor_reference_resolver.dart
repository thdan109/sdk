// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/element/member.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/resolver.dart';

/// A resolver for [ConstructorReference] nodes.
class ConstructorReferenceResolver {
  /// The resolver driving this participant.
  final ResolverVisitor _resolver;

  ConstructorReferenceResolver(this._resolver);

  void resolve(ConstructorReferenceImpl node) {
    if (!_resolver.isConstructorTearoffsEnabled &&
        node.constructorName.type.typeArguments == null) {
      // Only report this if [node] has no explicit type arguments; otherwise
      // the parser has already reported an error.
      _resolver.errorReporter.reportErrorForNode(
          CompileTimeErrorCode.CONSTRUCTOR_TEAROFFS_NOT_ENABLED, node, []);
    }
    node.constructorName.accept(_resolver);
    _inferArgumentTypes(node);
  }

  void _inferArgumentTypes(ConstructorReferenceImpl node) {
    var constructorName = node.constructorName;
    var typeName = constructorName.type;
    var elementToInfer = _resolver.inferenceHelper.constructorElementToInfer(
      constructorName: constructorName,
      definingLibrary: _resolver.definingLibrary,
    );

    // If the constructor is generic, we'll have a ConstructorMember that
    // substitutes in type arguments (possibly `dynamic`) from earlier in
    // resolution.
    //
    // Otherwise we'll have a ConstructorElement, and we can skip inference
    // because there's nothing to infer in a non-generic type.
    if (elementToInfer != null) {
      // TODO(leafp): Currently, we may re-infer types here, since we
      // sometimes resolve multiple times.  We should really check that we
      // have not already inferred something.  However, the obvious ways to
      // check this don't work, since we may have been instantiated
      // to bounds in an earlier phase, and we *do* want to do inference
      // in that case.

      // Get back to the uninstantiated generic constructor.
      // TODO(jmesserly): should we store this earlier in resolution?
      // Or look it up, instead of jumping backwards through the Member?
      var rawElement = elementToInfer.element;
      var constructorType = elementToInfer.asType;

      var inferred = _resolver.inferenceHelper.inferTearOff(
          node, constructorName.name!, constructorType) as FunctionType?;

      if (inferred != null) {
        typeName.type = inferred.returnType;

        // Update the static element as well. This is used in some cases, such
        // as computing constant values. It is stored in two places.
        var constructorElement = ConstructorMember.from(
          rawElement,
          inferred.returnType as InterfaceType,
        );
        constructorName.staticElement = constructorElement;
        constructorName.name?.staticElement = constructorElement;
        node.staticType = inferred;
      }
    } else {
      node.staticType = node.constructorName.staticElement!.type;
    }
  }
}
