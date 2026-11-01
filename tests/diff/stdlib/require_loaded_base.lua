-- expect: pass
-- stage: stdlib
-- feature: package
-- normalize: none

print(package.loaded._G == _G)
print(require("_G") == _G)
