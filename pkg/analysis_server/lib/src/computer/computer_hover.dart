// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/protocol/protocol_generated.dart'
    show HoverInformation;
import 'package:analysis_server/src/computer/computer_overrides.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/ast/element_locator.dart';
import 'package:analyzer/src/dart/ast/utilities.dart';
import 'package:analyzer/src/dartdoc/dartdoc_directive_info.dart';
import 'package:path/path.dart' as path;

/**
 * A computer for the hover at the specified offset of a Dart [CompilationUnit].
 */
class DartUnitHoverComputer {
  final DartdocDirectiveInfo _dartdocInfo;
  final CompilationUnit _unit;
  final int _offset;

  DartUnitHoverComputer(this._dartdocInfo, this._unit, this._offset);

  bool get _isNonNullableByDefault {
    return _unit.declaredElement.library.isNonNullableByDefault;
  }

  /**
   * Returns the computed hover, maybe `null`.
   */
  HoverInformation compute() {
    AstNode node = NodeLocator(_offset).searchWithin(_unit);
    if (node == null) {
      return null;
    }
    if (node.parent is TypeName &&
        node.parent.parent is ConstructorName &&
        node.parent.parent.parent is InstanceCreationExpression) {
      node = node.parent.parent.parent;
    }
    if (node.parent is ConstructorName &&
        node.parent.parent is InstanceCreationExpression) {
      node = node.parent.parent;
    }
    if (node is Expression) {
      Expression expression = node;
      // For constructor calls the whole expression is selected (above) but this
      // results in the range covering the whole call so narrow it to just the
      // ConstructorName.
      HoverInformation hover = expression is InstanceCreationExpression
          ? HoverInformation(
              expression.constructorName.offset,
              expression.constructorName.length,
            )
          : HoverInformation(expression.offset, expression.length);
      // element
      Element element = ElementLocator.locate(expression);
      if (element != null) {
        // variable, if synthetic accessor
        if (element is PropertyAccessorElement) {
          PropertyAccessorElement accessor = element;
          if (accessor.isSynthetic) {
            element = accessor.variable;
          }
        }
        // description
        hover.elementDescription = _elementDisplayString(element);
        if (node is InstanceCreationExpression && node.keyword == null) {
          String prefix = node.isConst ? '(const) ' : '(new) ';
          hover.elementDescription = prefix + hover.elementDescription;
        }
        hover.elementKind = element.kind.displayName;
        hover.isDeprecated = element.hasDeprecated;
        // not local element
        if (element.enclosingElement is! ExecutableElement) {
          // containing class
          ClassElement containingClass = element.thisOrAncestorOfType();
          if (containingClass != null) {
            hover.containingClassDescription = containingClass.displayName;
          }
          // containing library
          LibraryElement library = element.library;
          if (library != null) {
            Uri uri = library.source.uri;
            if (uri.scheme != '' && uri.scheme == 'file') {
              // for 'file:' URIs, use the path after the project root
              AnalysisSession analysisSession = _unit.declaredElement.session;
              path.Context context =
                  analysisSession.resourceProvider.pathContext;
              String projectRootDir =
                  analysisSession.analysisContext.contextRoot.root.path;
              String relativePath =
                  context.relative(context.fromUri(uri), from: projectRootDir);
              if (context.style == path.Style.windows) {
                List<String> pathList = context.split(relativePath);
                hover.containingLibraryName = pathList.join('/');
              } else {
                hover.containingLibraryName = relativePath;
              }
            } else {
              hover.containingLibraryName = uri.toString();
            }
            hover.containingLibraryPath = library.source.fullName;
          }
        }
        // documentation
        hover.dartdoc = computeDocumentation(_dartdocInfo, element);
      }
      // parameter
      hover.parameter = _elementDisplayString(
        expression.staticParameterElement,
      );
      // types
      {
        AstNode parent = expression.parent;
        DartType staticType;
        if (element == null || element is VariableElement) {
          staticType = _getTypeOfDeclarationOrReference(node);
        }
        if (parent is MethodInvocation && parent.methodName == expression) {
          staticType = parent.staticInvokeType;
          if (staticType != null && staticType.isDynamic) {
            staticType = null;
          }
        }
        hover.staticType = _typeDisplayString(staticType);
      }
      // done
      return hover;
    }
    // not an expression
    return null;
  }

  String _elementDisplayString(Element element) {
    return element?.getDisplayString(
      withNullability: _isNonNullableByDefault,
    );
  }

  String _typeDisplayString(DartType type) {
    return type?.getDisplayString(withNullability: _isNonNullableByDefault);
  }

  static String computeDocumentation(
      DartdocDirectiveInfo dartdocInfo, Element element) {
    // TODO(dantup) We're reusing this in parameter information - move it
    // somewhere shared?
    if (element is FieldFormalParameterElement) {
      element = (element as FieldFormalParameterElement).field;
    }
    if (element is ParameterElement) {
      element = element.enclosingElement;
    }
    if (element == null) {
      // This can happen when the code is invalid, such as having a field formal
      // parameter for a field that does not exist.
      return null;
    }
    // The documentation of the element itself.
    if (element.documentationComment != null) {
      return dartdocInfo.processDartdoc(element.documentationComment);
    }
    // Look for documentation comments of overridden members.
    OverriddenElements overridden = findOverriddenElements(element);
    for (Element superElement in [
      ...overridden.superElements,
      ...overridden.interfaceElements
    ]) {
      String rawDoc = superElement.documentationComment;
      if (rawDoc != null) {
        Element interfaceClass = superElement.enclosingElement;
        return dartdocInfo.processDartdoc(rawDoc) +
            '\n\nCopied from `${interfaceClass.displayName}`.';
      }
    }
    return null;
  }

  static DartType _getTypeOfDeclarationOrReference(Expression node) {
    if (node is SimpleIdentifier) {
      var element = node.staticElement;
      if (element is VariableElement) {
        if (node.inDeclarationContext()) {
          return element.type;
        }
        var parent2 = node.parent.parent;
        if (parent2 is NamedExpression && parent2.name.label == node) {
          return element.type;
        }
      }
    }
    return node.staticType;
  }
}
