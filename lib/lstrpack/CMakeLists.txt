add_library(lstrpack STATIC lstrpack.c)
target_include_directories(lstrpack
	PUBLIC
		${CMAKE_CURRENT_SOURCE_DIR}
	PRIVATE
		${PROJECT_SOURCE_DIR}/lib/lua/src
		${LUA_INCLUDE_DIR}
)
