import 'package:analyzer/dart/element/element.dart';

import '../comments.dart';
import '../config.dart';
import '../types.dart';
import 'classes.dart';
import '../naming.dart';
import 'delegates.dart';
import 'functions.dart';

class Frame {
  static String printNamespace(
      CompilationUnitElement element, String namespace) {
    var code = new StringBuffer();
    code.writeln(printImports(element));

    code.writeln("namespace ${namespace}{");

    // Add delegates
    for (var delegate in element.functionTypeAliases) {
      code.writeln(Delegates.printDelegate(delegate));
    }

    // Add methods that are not inside a class in dart to a default class in c#
    var defaultClassName = Naming.DefaultClassName(element);
    code.writeln("internal static class ${defaultClassName}{");
    for (var topLevelVariable in element.topLevelVariables) {
      var type = Types.getDartTypeName(topLevelVariable.type);
      var name = Naming.getTopLevelVariableName(topLevelVariable);
      name = Naming.upperCamelCase(name);
      code.writeln("public static $type $name = default(${type});");
    }

    for (var function in element.functions) {
      code.writeln(Functions.printFunction(function));
    }
    code.writeln("}");

    // Interfaces for abstract classes
    for (var type in element.types.where((t) =>
        t.isAbstract == true && t.isValidMixin == false
        // Workaround for classes that are not correctly picked up as interfaces
        ||
        ["PageMetrics", "FixedExtentMetrics", "GestureArenaEntry"]
            .contains(t.name))) {
      code.writeln(Classes.printInterface(type));
    }

    // Add mixins and their interfaces
    for (var mxin in element.mixins) {
      code.writeln(Classes.printMixin(mxin));
    }
    // If its possibly a valid Mixin, we have to treat it as a Mixin.
    for (var mxin in element.types.where((t) => t.isValidMixin == true)) {
      code.writeln(Classes.printMixin(mxin));
    }

    // Classes
    // Where not a valid Mixin, because I already created a class in the Mixin section
    for (var type in element.types.where((t) => t.isValidMixin == false)) {
      code.writeln(Classes.printClass(type));
    }
    // Enums
    for (var type in element.enums) {
      code.writeln(printEnum(type));
    }

    code.writeln("}");
    return code.toString();
  }

  static String printImports(CompilationUnitElement element) {
    var imports = Config.defaultImports;
    for (var import in element.enclosingElement.imports
        .where((i) => i.importedLibrary != null)) {
      AddImport(import.importedLibrary, imports);
    }

    // This is a workaround since files in the material\animated_icons folder are utilizing the "part of" dart feature
    // "part of" acts like all files are in the same library and imports are not used here
    // Since we actually need the usings in c# and cant just put the files in one namespace (that would break other references)
    // we add the missing usings manually
    if (element.enclosingElement.identifier
        .contains("material/animated_icons")) {
      imports.add("FlutterSDK.Material.Animatedicons.Animatedicons");
      imports.add("FlutterSDK.Material.Animatedicons.Animatediconsdata");
    }

    // HACK: Remove Cupertino, while in Alpha
    return imports
        .where((x) {
          return !x.contains('Cupertino');
        })
        .map((import) => "using ${import};")
        .join("\n");
  }

  static void AddImport(LibraryElement import, List<String> allImports) {
    var name = import.identifier;

    // Skip imports that should get ignored
    if (Config.ignoredImports.contains(name)) return;

    if (name.contains("package:flutter/")) {
      if (import.exportedLibraries.length > 0) {
        // We need to add all sub-libraries of this library
        for (var subLibrary in import.exportedLibraries) {
          AddImport(subLibrary, allImports);
        }
      }

      // Skip container imports
      if (!name.contains("package:flutter/src/")) return;

      // Add the package itself
      name = name.replaceAll("package:flutter/src/", "");
      name = name.replaceAll(".dart", "");
      name = Config.rootNamespace +
          "." +
          name
              .split("/")
              .map((part) =>
                  Naming.getFormattedName(part, NameStyle.UpperCamelCase))
              .join(".");
    }

    // Check if import is within the FlutterSDK library and modify the import to use the correct namespace
    if (import != null &&
        import.identifier.replaceAll("/", "\\").contains(Config.sourcePath)) {
      name = Naming.namespaceFromIdentifier(import.identifier);
    }

    // Add import if it does not already exist
    if (!allImports.contains(name)) allImports.add(name);
  }

  static String printEnum(ClassElement element) {
    var name = Naming.getFormattedTypeName(element.name);
    var code = new StringBuffer();
    code.writeln("");
    Comments.appendComment(code, element);

    // if (element.hasProtected == true || element.isPrivate == true)
    //   code.write("internal ");
    // if (element.isPublic == true)
    // HACK: Making all public for the moment
    code.write("public ");

    code.writeln("enum ${name}{");
    code.writeln("");
    for (var value in element.fields.where((e) => e.isEnumConstant)) {
      Comments.appendComment(code, value);
      var fieldValue = value.name;
      fieldValue = Naming.upperCamelCase(fieldValue);
      fieldValue = Naming.escapeFixedWords(fieldValue);
      code.writeln(fieldValue + ",");
    }
    code.writeln("}");
    return code.toString();
  }
}
