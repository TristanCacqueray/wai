module Network.Wai.Middleware.RequestSizeLimit (requestSizeLimit) where

import Network.Wai
import Network.Wai.Request
import qualified Data.ByteString.Char8 as S8
import qualified Data.ByteString.Lazy as BSL
import           Data.Word                    (Word64)
import           Data.IORef              (newIORef, readIORef, writeIORef)
import Network.HTTP.Types.Status (requestEntityTooLarge413)
import qualified Data.ByteString.Lazy.Char8 as LS8

requestSizeLimit :: Word64 -> Middleware
requestSizeLimit maxLen app req sendResponse = do
  putStrLn "In request size limit"
  case requestBodyLength req of
    KnownLength actualLen -> if actualLen > maxLen then
      sendResponse (tooLargeResponse maxLen actualLen)
      else app req sendResponse
    ChunkedBody -> do
        ref <- newIORef maxLen
        let newReq = req
                { requestBody = do
                    bs <- getRequestBodyChunk req
                    remaining <- readIORef ref
                    let len = fromIntegral $ S8.length bs
                        remaining' = remaining - len
                    if remaining < len
                        then do
                            putStrLn "Too large; sending too large response here"
                            -- This won't work, because execution continues after sendResponse
                            sendResponse $ tooLargeResponse maxLen len
                            putStrLn "Too large; just sent too large response here"
                            pure ""
                        else do
                            writeIORef ref remaining'
                            return bs
                }
        app newReq sendResponse

tooLargeResponse :: Word64 -> Word64 -> Response
tooLargeResponse maxLen bodyLen = responseLBS
    requestEntityTooLarge413
    [("Content-Type", "text/plain")]
    (BSL.concat 
        [ "Request body too large to be processed. The maximum size is "
        , (LS8.pack (show maxLen))
        , " bytes; your request body was "
        , (LS8.pack (show bodyLen))
        , " bytes. If you're the developer of this site, you can configure the maximum length with the `maximumContentLength` or `maximumContentLengthIO` function on the Yesod typeclass."
        ])

-- Yesod implementation below

-- -- | Impose a limit on the size of the request body.
-- limitRequestBody :: Word64 -> W.Request -> IO W.Request
-- limitRequestBody maxLen req = do
--     ref <- newIORef maxLen
--     return req
--         { W.requestBody = do
--             bs <- W.requestBody req
--             remaining <- readIORef ref
--             let len = fromIntegral $ S8.length bs
--                 remaining' = remaining - len
--             if remaining < len
--                 then throwIO $ HCWai $ tooLargeResponse maxLen len
--                 else do
--                     writeIORef ref remaining'
--                     return bs
--         }