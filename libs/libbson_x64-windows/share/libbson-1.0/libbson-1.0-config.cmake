# Copyright 2009-present MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if(NOT libbson-1.0_FIND_QUIETLY)
    message(WARNING "This CMake package is deprecated. Prefer instead to use the \"bson-1.0\" package and link to mongo::bson_shared.")
endif()

set (BSON_MAJOR_VERSION 1)
set (BSON_MINOR_VERSION 30)
set (BSON_MICRO_VERSION 2)
set (BSON_VERSION 1.30.2)
set (BSON_VERSION_FULL 1.30.2)

include(CMakeFindDependencyMacro)
find_dependency(bson-1.0)

set (BSON_LIBRARY mongo::bson_shared)
set (BSON_LIBRARIES mongo::bson_shared)
